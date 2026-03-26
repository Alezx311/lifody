class_name EvolutionTracker
extends Node

## Tracks per-tick evolution metrics for visualization in the InfoPanel.
## Maintains two ring buffers (alive cell count + average fitness) and a
## list of named milestones (catalyst events, first cluster appearance, etc.)

const HISTORY_LEN: int = 200

## Ring buffers written at _head, oldest entry at (_head + 1) % HISTORY_LEN
var _cell_counts: PackedInt32Array = []
var _avg_fitness: PackedInt32Array = []  # stored as int = actual_float * 10
var _milestones: Array = []              # Array of {tick: int, label: String}

var _head: int = 0
var _count: int = 0   # how many entries have been written (capped at HISTORY_LEN)
var _first_cluster_seen: bool = false
var _last_tick: int = 0


func setup(g: LifeGrid, cm: ClusterManager) -> void:
	_cell_counts.resize(HISTORY_LEN)
	_avg_fitness.resize(HISTORY_LEN)
	g.tick_completed.connect(_on_tick)
	cm.clusters_updated.connect(_on_clusters)


func _on_tick(tick_num: int) -> void:
	_last_tick = tick_num


func _on_clusters(clusters: Array) -> void:
	var total_cells: int = 0
	var total_fitness: float = 0.0
	for cl in clusters:
		total_cells += (cl as Cluster).get_size()
		total_fitness += (cl as Cluster).fitness_score
	var avg: float = total_fitness / float(clusters.size()) if clusters.size() > 0 else 0.0

	if not _first_cluster_seen and clusters.size() > 0:
		_first_cluster_seen = true
		_add_milestone(_last_tick, "Перший кластер")

	_cell_counts[_head] = total_cells
	_avg_fitness[_head] = int(avg * 10.0)
	_head = (_head + 1) % HISTORY_LEN
	_count = mini(_count + 1, HISTORY_LEN)


func _add_milestone(tick: int, label: String) -> void:
	_milestones.append({"tick": tick, "label": label})
	if _milestones.size() > 20:
		_milestones.pop_front()


## Record a named event from outside (e.g. catalyst triggers in main.gd)
func record_event(tick: int, label: String) -> void:
	_add_milestone(tick, label)


## Returns up to n most recent cell-count values, oldest first.
func get_cell_history(n: int) -> Array:
	return _read_ring(_cell_counts, n)


## Returns up to n most recent avg-fitness values (as float), oldest first.
func get_fitness_history(n: int) -> Array:
	var raw := _read_ring(_avg_fitness, n)
	var result: Array = []
	result.resize(raw.size())
	for i in raw.size():
		result[i] = raw[i] / 10.0
	return result


func get_milestones() -> Array:
	return _milestones


func get_last_tick() -> int:
	return _last_tick


## Internal: read up to n entries from a ring buffer, oldest first.
func _read_ring(buf: PackedInt32Array, n: int) -> Array:
	var available: int = mini(n, _count)
	if available == 0:
		return []
	var result: Array = []
	result.resize(available)
	# start index: walk backward from _head
	var start: int = (_head - available + HISTORY_LEN) % HISTORY_LEN
	for i in available:
		result[i] = buf[(start + i) % HISTORY_LEN]
	return result
