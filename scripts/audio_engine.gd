class_name AudioEngine
extends Node

## Sample-based audio engine with look-ahead scheduling.
##
## Architecture:
##   - SampleBank loads .ogg files for 8 instruments.
##   - A pool of AudioStreamPlayer nodes (POOL_SIZE voices) handles polyphony.
##   - Per-cluster schedulers maintain a "schedule_head" (absolute time in seconds).
##     Each call to play_clusters() extends every scheduler's queue up to
##     (now + LOOKAHEAD_SEC), so notes are always enqueued well ahead of playback.
##   - _process() fires queued notes when their fire_time is reached.
##
## This decouples music from simulation ticks — the melody plays continuously
## at musical tempo regardless of how fast the Life grid runs.

const POOL_SIZE:     int   = 24    # max simultaneous voices
const LOOKAHEAD_SEC: float = 0.8   # seconds to schedule ahead each tick

## Instrument preset names (index matches SampleBank.FOLDERS)
const INSTRUMENT_NAMES: Array = [
	"Guitar", "Piano", "Organ", "Strings",
	"Acoustic", "Wind", "Bass", "Pad",
]

var _bank: SampleBank = null
var _tonal: TonalRegions = null
var _grid: LifeGrid = null

## Pool of voice slots
var _pool: Array = []   # Array of { player: AudioStreamPlayer, end_time: float, midi: int }

## Look-ahead event queue, sorted loosely by fire_time
var _queue: Array = []  # Array of { fire_time, midi, duration, velocity, articulation, instrument }

## Per-cluster scheduler state
var _schedulers: Dictionary = {}  # cluster_id → { note_index: int, schedule_head: float }

## Master volume 0–1
var master_volume: float = 0.7

## Active instrument index (0–7)
var current_instrument: int = 0

## Tempo: beats per second (default 120 BPM → 2 bps)
var _tempo_bps: float = 2.0

## Listening radius in grid cells (0 = hear everything)
var listening_radius: int = 20

## Legacy property kept for UI compatibility (had meaning in additive synthesis).
## With sample-based playback this has no effect.
var harmonic_mix: float = 1.0

## MIDI notes currently sounding — consumed by GameUI for piano keyboard animation
var active_midi_notes: Dictionary = {}


# ────────────────────────────────────────────────────────────────────────────
#  Initialisation
# ────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_bank = SampleBank.new()
	add_child(_bank)
	_bank.load_all()

	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append({"player": p, "end_time": 0.0, "midi": -1})

	set_process(true)


func setup_tonal(t: TonalRegions) -> void:
	_tonal = t


func setup_grid(g: LifeGrid) -> void:
	_grid = g


func set_tempo(bpm: float) -> void:
	_tempo_bps = bpm / 60.0


func set_instrument(idx: int) -> void:
	current_instrument = clampi(idx, 0, INSTRUMENT_NAMES.size() - 1)


func get_instrument_name() -> String:
	return INSTRUMENT_NAMES[current_instrument]


# ────────────────────────────────────────────────────────────────────────────
#  Public: receive clusters each tick and extend the look-ahead schedule
# ────────────────────────────────────────────────────────────────────────────

func play_clusters(clusters: Array) -> void:
	if not _bank.is_loaded or _tonal == null:
		return

	var now: float    = _now()
	var horizon: float = now + LOOKAHEAD_SEC

	# Listening centre: follow mouse on the grid
	var listen_center := Vector2i(LifeGrid.GRID_W / 2, LifeGrid.GRID_H / 2)
	if _grid != null:
		var local_mouse: Vector2 = _grid.to_local(_grid.get_global_mouse_position())
		listen_center = _grid.pixel_to_grid(local_mouse)
	if _grid != null:
		listening_radius = _grid.listening_radius

	# Collect live cluster IDs and their distances to the listener
	var live_ids: Dictionary = {}
	for cl_raw in clusters:
		var cl := cl_raw as Cluster
		live_ids[cl.id] = _cluster_distance(cl, listen_center)

	# Drop schedulers for dead / out-of-range clusters
	for cid in _schedulers.keys().duplicate():
		if not live_ids.has(cid):
			_schedulers.erase(cid)
		elif listening_radius > 0 and live_ids[cid] > float(listening_radius):
			_schedulers.erase(cid)

	# Sort clusters by distance; limit to POOL_SIZE/2 nearest
	var in_range: Array = []
	for cl_raw in clusters:
		var cl := cl_raw as Cluster
		if cl.melody.is_empty():
			continue
		var dist: float = live_ids.get(cl.id, 9999.0)
		if listening_radius > 0 and dist > float(listening_radius):
			continue
		in_range.append({"cl": cl, "dist": dist})
	in_range.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["dist"] < b["dist"]
	)
	var max_cl: int = POOL_SIZE / 2
	if in_range.size() > max_cl:
		in_range = in_range.slice(0, max_cl)

	# Extend each cluster's schedule up to the horizon
	for entry in in_range:
		var cl  := entry["cl"] as Cluster
		var dist: float = entry["dist"]

		if not _schedulers.has(cl.id):
			_schedulers[cl.id] = {"note_index": 0, "schedule_head": now}

		var sched: Dictionary = _schedulers[cl.id]

		# If the scheduler fell behind (e.g. cluster was out of range), catch up
		if sched["schedule_head"] < now:
			sched["schedule_head"] = now

		# Volume: quadratic distance falloff
		var vol_factor: float = 1.0
		if listening_radius > 0:
			vol_factor = 1.0 - clampf(dist / float(listening_radius), 0.0, 1.0)
			vol_factor *= vol_factor

		# Fill queue up to horizon
		while sched["schedule_head"] < horizon:
			var melody: Array = cl.melody
			if melody.is_empty():
				break
			var idx: int     = sched["note_index"] % melody.size()
			var note := melody[idx] as DNANote

			var region: int  = _get_cell_region(cl)
			var midi: int    = _tonal.pitch_to_midi(note.pitch, region, cl.get_octave_offset())
			var dur: float   = _note_duration_sec(note)
			var vel: float   = clampf(
				float(note.velocity) / 127.0 * cl.get_volume_scale() * master_volume * vol_factor,
				0.0, 1.0)

			# Articulation: modify velocity and rhythm spacing
			match note.articulation:
				1: vel *= 0.75; dur *= 0.45          # staccato — quieter, shorter gap
				2: dur *= 1.4                         # tenuto — wider gap, fuller sound
				3: vel = minf(vel * 1.35, 1.0)       # accent — louder attack

			_queue.append({
				"fire_time":   sched["schedule_head"],
				"midi":        midi,
				"duration":    dur,
				"velocity":    vel,
				"articulation": note.articulation,
				"instrument":  current_instrument,
			})

			sched["schedule_head"] += dur
			sched["note_index"] = (idx + 1) % melody.size()


# ────────────────────────────────────────────────────────────────────────────
#  _process: fire queued notes and clean up finished voices
# ────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	var now: float = _now()

	# Fire any notes whose time has arrived
	var remaining: Array = []
	for ev in _queue:
		if (ev as Dictionary)["fire_time"] <= now:
			_fire_voice(ev)
		else:
			remaining.append(ev)
	_queue = remaining

	# Clean up active_midi_notes for voices that have finished
	for slot in _pool:
		var s := slot as Dictionary
		if s["midi"] >= 0 and now >= s["end_time"]:
			_decrement_active(s["midi"])
			s["midi"] = -1


# ────────────────────────────────────────────────────────────────────────────
#  Voice allocation
# ────────────────────────────────────────────────────────────────────────────

func _fire_voice(ev: Dictionary) -> void:
	if not _bank.is_loaded:
		return
	var info: Dictionary = _bank.get_sample(ev["instrument"], ev["midi"])
	if info.is_empty():
		return

	var slot: Dictionary = _get_free_slot()
	var player := slot["player"] as AudioStreamPlayer

	player.stream      = info["stream"]
	player.pitch_scale = info["pitch_scale"]
	player.volume_db   = linear_to_db(maxf(ev["velocity"], 0.001))
	player.play()

	slot["end_time"] = _now() + ev["duration"]
	slot["midi"]     = ev["midi"]
	active_midi_notes[ev["midi"]] = active_midi_notes.get(ev["midi"], 0) + 1


func _get_free_slot() -> Dictionary:
	# Prefer a player that has finished naturally
	var now: float = _now()
	for slot in _pool:
		var s := slot as Dictionary
		if not (s["player"] as AudioStreamPlayer).playing:
			return s
	# Steal the slot whose note ends soonest
	var oldest: Dictionary = _pool[0]
	for slot in _pool:
		var s := slot as Dictionary
		if s["end_time"] < oldest["end_time"]:
			oldest = s
	_decrement_active(oldest["midi"])
	(oldest["player"] as AudioStreamPlayer).stop()
	oldest["midi"] = -1
	return oldest


func _decrement_active(midi: int) -> void:
	if midi < 0:
		return
	var cnt: int = active_midi_notes.get(midi, 0) - 1
	if cnt <= 0:
		active_midi_notes.erase(midi)
	else:
		active_midi_notes[midi] = cnt


# ────────────────────────────────────────────────────────────────────────────
#  Helpers
# ────────────────────────────────────────────────────────────────────────────

## Monotonic time in seconds (high-resolution).
func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


func _note_duration_sec(note: DNANote) -> float:
	# duration field = sixteenth-note units; 4 sixteenths = 1 beat
	return float(note.duration) / (4.0 * _tempo_bps)


func _cluster_distance(cl: Cluster, center: Vector2i) -> float:
	if cl.cells.is_empty():
		return 9999.0
	var sum := Vector2i.ZERO
	for p in cl.cells:
		sum += p as Vector2i
	return Vector2(sum / cl.cells.size() - center).length()


func _get_cell_region(cl: Cluster) -> int:
	if cl.cells.is_empty() or _grid == null:
		return _tonal.get_region_id(0, 0) if _tonal else 0
	var pos := cl.cells[0] as Vector2i
	return _grid.cells[pos.y][pos.x].tonal_region


## Directly play a single MIDI note (UI feedback, DNA injection preview).
func play_midi_note(midi: int, duration_sec: float, velocity: float = 0.7) -> void:
	if not _bank.is_loaded:
		return
	var info: Dictionary = _bank.get_sample(current_instrument, midi)
	if info.is_empty():
		return
	var slot: Dictionary = _get_free_slot()
	var player := slot["player"] as AudioStreamPlayer
	player.stream      = info["stream"]
	player.pitch_scale = info["pitch_scale"]
	player.volume_db   = linear_to_db(maxf(velocity * master_volume, 0.001))
	player.play()
	slot["end_time"] = _now() + duration_sec
	slot["midi"]     = midi
	active_midi_notes[midi] = active_midi_notes.get(midi, 0) + 1
