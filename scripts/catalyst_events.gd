class_name CatalystEvents
extends Node

## One-shot dramatic events available to the player.
## Players receive one event token every 50 ticks, can hold up to 3.

signal event_tokens_changed(count: int)
signal status_message(msg: String)

const TOKEN_INTERVAL: int = 50
const MAX_TOKENS: int = 3

var grid: LifeGrid = null
var cluster_mgr: ClusterManager = null
var fitness_mgr: FitnessManager = null

var tokens: int = 1   # start with one token


func setup(g: LifeGrid, cm: ClusterManager, fm: FitnessManager) -> void:
	grid = g
	cluster_mgr = cm
	fitness_mgr = fm


func on_tick(tick_num: int) -> void:
	if tick_num > 0 and tick_num % TOKEN_INTERVAL == 0:
		if tokens < MAX_TOKENS:
			tokens += 1
			event_tokens_changed.emit(tokens)
			status_message.emit("New event token! (%d/%d)" % [tokens, MAX_TOKENS])


func _spend_token() -> bool:
	if tokens <= 0:
		status_message.emit("No event tokens left!")
		return false
	tokens -= 1
	event_tokens_changed.emit(tokens)
	return true


# ────────────────────────────────────────────────────────────────────────────
#  ☄️  Meteorite — kills area, survivors scatter as spores
# ────────────────────────────────────────────────────────────────────────────

func event_meteorite(cx: int, cy: int, radius: int = 8) -> void:
	if not _spend_token():
		return

	var spores: Array = []  # {genome, fitness}

	for y in LifeGrid.GRID_H:
		for x in LifeGrid.GRID_W:
			var d: float = Vector2(x - cx, y - cy).length()
			if d <= radius:
				var cell: CellState = grid.cells[y][x]
				if cell.alive:
					var cl := cluster_mgr.get_cluster_at(x, y)
					var fit: float = cl.fitness_score if cl else 50.0
					if randf() < fit / 100.0:
						spores.append({"genome": cell.genome.duplicate(true), "fitness": fit})
					grid.cells[y][x] = CellState.new()

	# Scatter spores outside impact radius
	for spore in spores:
		_scatter_spore(spore["genome"], cx, cy, radius + 2)

	grid.queue_redraw()
	status_message.emit("☄️ Meteorite! %d spores scattered." % spores.size())


func _scatter_spore(genome: Array, cx: int, cy: int, min_dist: int) -> void:
	for _attempt in range(30):
		var angle: float = randf() * TAU
		var dist: float = randf_range(float(min_dist), float(min_dist + 12))
		var sx: int = int(cx + cos(angle) * dist)
		var sy: int = int(cy + sin(angle) * dist)
		if sx < 0 or sx >= LifeGrid.GRID_W or sy < 0 or sy >= LifeGrid.GRID_H:
			continue
		if not grid.cells[sy][sx].alive:
			grid.cells[sy][sx] = CellState.create_alive(genome)
			if grid.tonal:
				grid.cells[sy][sx].tonal_region = grid.tonal.get_region_id(sx, sy)
			return


# ────────────────────────────────────────────────────────────────────────────
#  🤝  Resonance — teleport two melodically similar clusters together
# ────────────────────────────────────────────────────────────────────────────

func event_resonance() -> void:
	if not _spend_token():
		return

	var cls := cluster_mgr.clusters
	if cls.size() < 2:
		status_message.emit("Need at least 2 clusters for Resonance.")
		tokens += 1  # refund
		event_tokens_changed.emit(tokens)
		return

	# Find the most similar pair by pitch edit distance
	var best_a: Cluster = null
	var best_b: Cluster = null
	var best_sim: float = -1.0

	for i in range(cls.size()):
		for j in range(i + 1, cls.size()):
			var sim := fitness_mgr._melody_similarity(
				(cls[i] as Cluster).melody,
				(cls[j] as Cluster).melody
			)
			if sim > best_sim:
				best_sim = sim
				best_a = cls[i]
				best_b = cls[j]

	if best_a == null:
		return

	# Move cluster B toward cluster A (within 10 cells)
	var ca := _cluster_center(best_a)
	_teleport_cluster_near(best_b, ca, 10)
	grid.queue_redraw()
	status_message.emit("🤝 Resonance: clusters %.0f%% similar brought together." % (best_sim * 100))


func _cluster_center(cl: Cluster) -> Vector2i:
	if cl.cells.is_empty():
		return Vector2i.ZERO
	var sum := Vector2i.ZERO
	for p in cl.cells:
		sum += p as Vector2i
	return sum / cl.cells.size()


func _teleport_cluster_near(cl: Cluster, target: Vector2i, max_radius: int) -> void:
	var center := _cluster_center(cl)
	var offset := target - center
	# Clamp offset magnitude
	var length: float = Vector2(offset).length()
	if length > max_radius:
		offset = Vector2i(Vector2(offset).normalized() * max_radius)

	var new_cells_state: Dictionary = {}
	for pos in cl.cells:
		var v := pos as Vector2i
		var nv := Vector2i(clampi(v.x + offset.x, 0, LifeGrid.GRID_W - 1),
						   clampi(v.y + offset.y, 0, LifeGrid.GRID_H - 1))
		new_cells_state[nv] = grid.cells[v.y][v.x].copy()
		grid.cells[v.y][v.x] = CellState.new()

	for nv in new_cells_state:
		var v2 := nv as Vector2i
		grid.cells[v2.y][v2.x] = new_cells_state[nv]


# ────────────────────────────────────────────────────────────────────────────
#  ❄️  Freeze — crystallise a cluster for 20 ticks
# ────────────────────────────────────────────────────────────────────────────

func event_freeze(cluster_id: int) -> void:
	if not _spend_token():
		return
	var cl := cluster_mgr.get_cluster_by_id(cluster_id)
	if cl == null:
		status_message.emit("No cluster selected to freeze.")
		tokens += 1
		event_tokens_changed.emit(tokens)
		return
	grid.freeze_cells(cl.cells, true)
	# Schedule unfreeze after 20 ticks using a one-shot timer
	var timer := get_tree().create_timer(20.0 * grid.tick_interval)
	timer.timeout.connect(func() -> void:
		grid.freeze_cells(cl.cells, false)
		status_message.emit("❄️ Cluster thawed.")
	)
	status_message.emit("❄️ Cluster frozen for 20 ticks — it will spread its DNA!")


# ────────────────────────────────────────────────────────────────────────────
#  🌊  Mutation Wave — global chaos for 10 ticks
# ────────────────────────────────────────────────────────────────────────────

func event_mutation_wave() -> void:
	if not _spend_token():
		return
	var saved_rate: float = grid.base_mutation_rate
	grid.base_mutation_rate = saved_rate * 5.0
	# Reset all fitness to 50
	for cl in cluster_mgr.clusters:
		(cl as Cluster).fitness_score = 50.0
		cluster_mgr.update_fitness((cl as Cluster).id, 0.0)
	var timer := get_tree().create_timer(10.0 * grid.tick_interval)
	timer.timeout.connect(func() -> void:
		grid.base_mutation_rate = saved_rate
		status_message.emit("🌊 Mutation wave subsided.")
	)
	status_message.emit("🌊 Mutation wave! All fitness reset. 10 ticks of chaos.")


# ────────────────────────────────────────────────────────────────────────────
#  🎭  Mirror — duplicate cluster with inverted melody on opposite side
# ────────────────────────────────────────────────────────────────────────────

func event_mirror(cluster_id: int) -> void:
	if not _spend_token():
		return
	var cl := cluster_mgr.get_cluster_by_id(cluster_id)
	if cl == null:
		status_message.emit("No cluster to mirror.")
		tokens += 1
		event_tokens_changed.emit(tokens)
		return

	var center := _cluster_center(cl)
	var mirror_offset := Vector2i(LifeGrid.GRID_W - 1 - center.x * 2,
								  LifeGrid.GRID_H - 1 - center.y * 2)

	# Invert melody order
	var inv_melody := cl.melody.duplicate()
	inv_melody.reverse()

	for pos in cl.cells:
		var v := pos as Vector2i
		var mv := Vector2i(
			clampi(v.x + mirror_offset.x, 0, LifeGrid.GRID_W - 1),
			clampi(v.y + mirror_offset.y, 0, LifeGrid.GRID_H - 1)
		)
		if not grid.cells[mv.y][mv.x].alive:
			var original_cell: CellState = grid.cells[v.y][v.x]
			var new_cell := original_cell.copy()
			# Reverse genome
			new_cell.genome.reverse()
			grid.cells[mv.y][mv.x] = new_cell
			if grid.tonal:
				grid.cells[mv.y][mv.x].tonal_region = grid.tonal.get_region_id(mv.x, mv.y)

	grid.queue_redraw()
	status_message.emit("🎭 Cluster mirrored with inverted melody!")
