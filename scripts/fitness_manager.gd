class_name FitnessManager
extends Node

## Manages player-driven fitness feedback and natural fitness decay.
## Fitness shapes survival probability in LifeGrid._next_generation().

signal fitness_changed(cluster_id: int, new_score: float)

var cluster_mgr: ClusterManager = null
var audio_engine: AudioEngine = null

## Library of saved melodies: Array of {name, melody: Array[DNANote]}
var melody_library: Array = []

## Per-cluster mute state (cluster_id → bool)
var muted_clusters: Dictionary = {}

## Cache of last-computed library bonus per cluster (recomputed every 10 ticks).
var _last_lib_bonus: Dictionary = {}  # cluster_id → float

## Rewind budget (3 per session)
var rewinds_left: int = 3

## DNA injection cooldown
var inject_cooldown: int = 0
const INJECT_COOLDOWN_TICKS: int = 15


func setup(cm: ClusterManager, ae: AudioEngine) -> void:
	cluster_mgr = cm
	audio_engine = ae


# ────────────────────────────────────────────────────────────────────────────
#  Called every tick by main
# ────────────────────────────────────────────────────────────────────────────

func on_tick(_tick_num: int) -> void:
	if inject_cooldown > 0:
		inject_cooldown -= 1

	var lib_check: bool = (_tick_num % 10 == 0)
	var alive_ids: Dictionary = {}

	for cl in cluster_mgr.clusters:
		var cid: int = (cl as Cluster).id
		alive_ids[cid] = true
		# Natural decay
		(cl as Cluster).tick_decay()
		# Stable cluster bonus (reduced from +5.0 to +0.5; decay is -0.1/tick so net ~+0.4)
		if (cl as Cluster).state == "stable":
			(cl as Cluster).modify_fitness(0.5)
		# Library similarity bonus — recomputed every 10 ticks, applied only then
		if lib_check:
			var bonus: float = _library_bonus(cl as Cluster)
			_last_lib_bonus[cid] = bonus
			if bonus > 0.0:
				(cl as Cluster).modify_fitness(bonus)
		cluster_mgr.update_fitness(cid, 0.0)  # sync fitness store
		fitness_changed.emit(cid, (cl as Cluster).fitness_score)

	# Evict cached bonuses for dead clusters
	for cid in _last_lib_bonus.keys().duplicate():
		if not alive_ids.has(cid):
			_last_lib_bonus.erase(cid)


# ────────────────────────────────────────────────────────────────────────────
#  Player actions
# ────────────────────────────────────────────────────────────────────────────

## Player likes a cluster: +15 fitness.
func like_cluster(cluster_id: int) -> void:
	cluster_mgr.update_fitness(cluster_id, 15.0)
	var cl := cluster_mgr.get_cluster_by_id(cluster_id)
	if cl:
		fitness_changed.emit(cluster_id, cl.fitness_score)


## Player mutes/unmutes a cluster: −20 fitness and silence.
func mute_cluster(cluster_id: int) -> void:
	var current: bool = muted_clusters.get(cluster_id, false)
	muted_clusters[cluster_id] = not current
	if not current:
		cluster_mgr.update_fitness(cluster_id, -20.0)
	var cl := cluster_mgr.get_cluster_by_id(cluster_id)
	if cl:
		fitness_changed.emit(cluster_id, cl.fitness_score)


func is_muted(cluster_id: int) -> bool:
	return muted_clusters.get(cluster_id, false)


## Save current cluster melody to library.
func save_melody(cluster_id: int, name: String = "") -> bool:
	var cl := cluster_mgr.get_cluster_by_id(cluster_id)
	if cl == null or cl.melody.is_empty():
		return false
	var copy_melody: Array = []
	for n in cl.melody:
		copy_melody.append((n as DNANote).copy())
	var entry_name: String = name if name != "" else "Melody %d" % (melody_library.size() + 1)
	melody_library.append({"name": entry_name, "melody": copy_melody})
	return true


func delete_library_entry(idx: int) -> void:
	if idx >= 0 and idx < melody_library.size():
		melody_library.remove_at(idx)


# ────────────────────────────────────────────────────────────────────────────
#  Library similarity (Levenshtein-like on pitch sequences)
# ────────────────────────────────────────────────────────────────────────────

func _library_bonus(cl: Cluster) -> float:
	if melody_library.is_empty() or cl.melody.is_empty():
		return 0.0
	var best_sim: float = 0.0
	for entry in melody_library:
		var sim: float = _melody_similarity(cl.melody, entry["melody"])
		if sim > best_sim:
			best_sim = sim
	if best_sim > 0.7:
		return 10.0
	elif best_sim > 0.5:
		return 5.0
	return 0.0


## Returns 0-1 similarity between two melody arrays based on pitch edit distance.
func _melody_similarity(a: Array, b: Array) -> float:
	var la: int = mini(a.size(), 16)
	var lb: int = mini(b.size(), 16)
	if la == 0 or lb == 0:
		return 0.0

	# Simple pitch-sequence Levenshtein
	var dp: Array = []
	for i in range(la + 1):
		var row: Array = []
		for j in range(lb + 1):
			row.append(0)
		dp.append(row)
	for i in range(la + 1):
		dp[i][0] = i
	for j in range(lb + 1):
		dp[0][j] = j

	for i in range(1, la + 1):
		for j in range(1, lb + 1):
			var cost: int = 0 if (a[i-1] as DNANote).pitch == (b[j-1] as DNANote).pitch else 1
			dp[i][j] = mini(mini(dp[i-1][j] + 1, dp[i][j-1] + 1), dp[i-1][j-1] + cost)

	var max_len: int = maxi(la, lb)
	return 1.0 - float(dp[la][lb]) / float(max_len)


# ────────────────────────────────────────────────────────────────────────────
#  Rewind
# ────────────────────────────────────────────────────────────────────────────

func can_rewind() -> bool:
	return rewinds_left > 0


func use_rewind() -> bool:
	if rewinds_left <= 0:
		return false
	rewinds_left -= 1
	return true


# ────────────────────────────────────────────────────────────────────────────
#  DNA injection cooldown
# ────────────────────────────────────────────────────────────────────────────

func can_inject() -> bool:
	return inject_cooldown <= 0


func trigger_inject_cooldown() -> void:
	inject_cooldown = INJECT_COOLDOWN_TICKS
