class_name AudioEngine
extends Node

## Pure GDScript audio synthesis via AudioStreamGenerator.
## Plays melodic notes from cluster genomes using additive sine-wave synthesis
## with full ADSR envelopes. Supports multiple simultaneous voices (polyphony).
## 8 instrument presets with per-instrument harmonic stacks.

const SAMPLE_RATE: int = 44100
const BUFFER_LEN: float = 0.08   # seconds (80 ms latency)
const MAX_VOICES: int = 12       # hard polyphony limit — keep low to avoid crackling

## Instrument presets — each entry defines:
##   h[0..6] : harmonic amplitudes (fundamental + 6 overtones)
##   sub     : sub-octave (ph*0.5) amplitude
##   atk/dcy/sus/rel : ADSR in seconds (sus = sustain level 0-1)
##   vol     : per-instrument volume scale
const INSTRUMENTS: Array = [
	{"name": "Synth",   "h": [1.00, 0.35, 0.15, 0.00, 0.00, 0.00, 0.00], "sub": 0.10,
	 "atk": 0.010, "dcy": 0.050, "sus": 0.85, "rel": 0.050, "vol": 1.00},
	{"name": "Piano",   "h": [1.00, 0.58, 0.28, 0.16, 0.08, 0.04, 0.02], "sub": 0.04,
	 "atk": 0.006, "dcy": 0.200, "sus": 0.50, "rel": 0.140, "vol": 0.70},
	{"name": "Organ",   "h": [1.00, 0.80, 0.60, 0.40, 0.25, 0.15, 0.08], "sub": 0.00,
	 "atk": 0.012, "dcy": 0.020, "sus": 0.95, "rel": 0.040, "vol": 0.48},
	{"name": "Strings", "h": [1.00, 0.42, 0.22, 0.12, 0.07, 0.03, 0.01], "sub": 0.00,
	 "atk": 0.090, "dcy": 0.100, "sus": 0.80, "rel": 0.180, "vol": 0.88},
	{"name": "Bell",    "h": [1.00, 0.00, 0.55, 0.00, 0.28, 0.00, 0.16], "sub": 0.00,
	 "atk": 0.004, "dcy": 0.380, "sus": 0.12, "rel": 0.320, "vol": 0.95},
	{"name": "Flute",   "h": [1.00, 0.18, 0.06, 0.02, 0.00, 0.00, 0.00], "sub": 0.00,
	 "atk": 0.055, "dcy": 0.080, "sus": 0.75, "rel": 0.100, "vol": 1.10},
	{"name": "Bass",    "h": [1.00, 0.45, 0.22, 0.10, 0.05, 0.02, 0.00], "sub": 0.75,
	 "atk": 0.008, "dcy": 0.120, "sus": 0.60, "rel": 0.090, "vol": 0.82},
	{"name": "Pad",     "h": [1.00, 0.55, 0.35, 0.20, 0.12, 0.07, 0.04], "sub": 0.08,
	 "atk": 0.160, "dcy": 0.150, "sus": 0.88, "rel": 0.260, "vol": 0.78},
]

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _voices: Array = []     # Array of voice dicts
var _tonal: TonalRegions = null
var _tempo_bps: float = 2.0   # beats per second (120 BPM default)
var _grid: LifeGrid = null    # reference for tick_interval sync and mouse pos

## Per-cluster melody scheduler state
var _schedulers: Dictionary = {}  # cluster_id → scheduler dict

## Master volume 0-1
var master_volume: float = 0.7

## Harmonic mix: 0 = pure fundamental only, 1 = full overtone stack
var harmonic_mix: float = 1.0

## Active instrument index (0..7)
var current_instrument: int = 0

## Listening zone — only clusters whose centre is within this radius (grid cells) are heard.
## Set to 0 to hear everything.
var listening_radius: int = 20

## Set of MIDI notes currently sounding: midi → voice count.
## Consumed by GameUI to animate the piano keyboard.
var active_midi_notes: Dictionary = {}


# ────────────────────────────────────────────────────────────────────────────
#  Initialisation
# ────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = BUFFER_LEN

	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = 0.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	set_process(true)


func setup_tonal(t: TonalRegions) -> void:
	_tonal = t


func setup_grid(g: LifeGrid) -> void:
	_grid = g


func set_tempo(bpm: float) -> void:
	_tempo_bps = bpm / 60.0


func set_instrument(idx: int) -> void:
	current_instrument = clampi(idx, 0, INSTRUMENTS.size() - 1)


func get_instrument_name() -> String:
	return (INSTRUMENTS[current_instrument] as Dictionary).get("name", "?")


# ────────────────────────────────────────────────────────────────────────────
#  Public: receive clusters each tick
# ────────────────────────────────────────────────────────────────────────────

func play_clusters(clusters: Array) -> void:
	# Determine listening centre from mouse position on grid
	var listen_center := Vector2i(LifeGrid.GRID_W / 2, LifeGrid.GRID_H / 2)
	if _grid != null:
		var local_mouse: Vector2 = _grid.to_local(_grid.get_global_mouse_position())
		listen_center = _grid.pixel_to_grid(local_mouse)

	# Sync listening_radius to grid's value
	if _grid != null:
		listening_radius = _grid.listening_radius

	# Mark live cluster ids; compute distance to listener
	var live_ids: Dictionary = {}
	for cl_raw in clusters:
		var cl := cl_raw as Cluster
		live_ids[cl.id] = _cluster_distance(cl, listen_center)

	# Remove schedulers for clusters that are dead or out of range
	for cid in _schedulers.keys().duplicate():
		if not live_ids.has(cid):
			_schedulers.erase(cid)
		elif listening_radius > 0 and live_ids[cid] > listening_radius:
			_schedulers.erase(cid)

	# Sort clusters by distance and cap to MAX_VOICES / 2 closest ones
	var in_range: Array = []
	for cl_raw in clusters:
		var cl := cl_raw as Cluster
		if cl.melody.is_empty():
			continue
		var dist: float = live_ids.get(cl.id, 9999.0)
		if listening_radius > 0 and dist > listening_radius:
			continue
		in_range.append({"cl": cl, "dist": dist})
	in_range.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["dist"] < b["dist"]
	)
	var max_clusters: int = MAX_VOICES / 2
	if in_range.size() > max_clusters:
		in_range = in_range.slice(0, max_clusters)

	# Advance each scheduler
	var tick_sec: float = _get_tick_seconds()
	for entry in in_range:
		var cl := entry["cl"] as Cluster
		var dist: float = entry["dist"]

		if not _schedulers.has(cl.id):
			_schedulers[cl.id] = {"index": 0, "timer": 0.0}

		var sched: Dictionary = _schedulers[cl.id]
		sched["timer"] = maxf(sched["timer"] - tick_sec, 0.0)

		if sched["timer"] <= 0.0:
			var idx: int = sched["index"]
			var note := cl.melody[idx % cl.melody.size()] as DNANote
			# Volume falloff based on distance
			var vol_factor: float = 1.0
			if listening_radius > 0:
				vol_factor = 1.0 - clampf(dist / float(listening_radius), 0.0, 1.0)
				vol_factor = vol_factor * vol_factor  # quadratic falloff
			_schedule_note_from_genome(note, cl, 0.01, vol_factor)
			var dur: float = _note_duration_sec(note)
			sched["timer"] = dur
			sched["index"] = (idx + 1) % cl.melody.size()


func _cluster_distance(cl: Cluster, center: Vector2i) -> float:
	if cl.cells.is_empty():
		return 9999.0
	var sum := Vector2i.ZERO
	for p in cl.cells:
		sum += p as Vector2i
	var cl_center: Vector2i = sum / cl.cells.size()
	return Vector2(cl_center - center).length()


func _get_tick_seconds() -> float:
	if _grid != null:
		return _grid.tick_interval
	return 0.2


func _schedule_note_from_genome(note: DNANote, cl: Cluster, delay: float, vol_factor: float = 1.0) -> void:
	if _tonal == null:
		return
	if cl.cells.is_empty():
		return
	var first_pos: Vector2i = cl.cells[0] as Vector2i
	# Use the cell's stored region (important for chromatic cells)
	var region: int = _grid.cells[first_pos.y][first_pos.x].tonal_region if _grid else \
					  _tonal.get_region_id(first_pos.x, first_pos.y)

	var midi: int = _tonal.pitch_to_midi(note.pitch, region, cl.get_octave_offset())
	var dur_sec: float = _note_duration_sec(note)
	var vel: float = float(note.velocity) / 127.0 * cl.get_volume_scale() * master_volume * vol_factor

	_add_voice(midi, dur_sec, vel, note.articulation, delay)


func _note_duration_sec(note: DNANote) -> float:
	# duration field is in sixteenth-note units; 4 sixteenths = 1 beat
	return float(note.duration) / (4.0 * _tempo_bps)


## Directly play a single MIDI note (for UI feedback, DNA injection preview, etc.)
func play_midi_note(midi: int, duration_sec: float, velocity: float = 0.7) -> void:
	_add_voice(midi, duration_sec, velocity * master_volume, 0, 0.0)


# ────────────────────────────────────────────────────────────────────────────
#  Voice management
# ────────────────────────────────────────────────────────────────────────────

func _add_voice(midi: int, dur: float, vel: float, articulation: int, delay: float) -> void:
	if _voices.size() >= MAX_VOICES:
		# Drop the oldest voice to make room, tracking its midi note
		var dropped: Dictionary = _voices.pop_front()
		_decrement_active(dropped.get("midi", -1))

	var freq: float = 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)

	# Pull base ADSR from the current instrument
	var inst: Dictionary = INSTRUMENTS[current_instrument]
	var attack: float  = inst["atk"]
	var decay: float   = inst["dcy"]
	var sustain: float = inst["sus"]
	var release: float = inst["rel"]
	vel = minf(vel * float(inst["vol"]), 1.0)

	# Articulation modifiers
	match articulation:
		1: dur = dur * 0.4;      release = release * 0.4   # staccato — short, quick release
		2: attack = attack * 2.0; release = release * 1.5  # tenuto — slower attack/release
		3: attack = attack * 0.5; vel = minf(vel * 1.3, 1.0)  # accent — sharp attack, louder

	_voices.append({
		"midi":    midi,
		"freq":    freq,
		"phase":   0.0,
		"vel":     vel,
		"attack":  attack,
		"decay":   decay,
		"sustain": sustain,
		"release": release,
		"dur":     dur,
		"delay":   delay,
		"elapsed": -delay,
	})
	active_midi_notes[midi] = active_midi_notes.get(midi, 0) + 1


func _decrement_active(midi: int) -> void:
	if midi < 0:
		return
	var cnt: int = active_midi_notes.get(midi, 0) - 1
	if cnt <= 0:
		active_midi_notes.erase(midi)
	else:
		active_midi_notes[midi] = cnt


# ────────────────────────────────────────────────────────────────────────────
#  Audio processing loop
# ────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames: int = _playback.get_frames_available()
	if frames == 0:
		return

	var dt: float = 1.0 / float(SAMPLE_RATE)
	var to_fill: int = mini(frames, SAMPLE_RATE / 20)  # max 50 ms per _process

	# Cache per-instrument profile outside the inner loops
	var inst: Dictionary = INSTRUMENTS[current_instrument]
	var ih: Array = inst["h"]
	var isub: float = inst["sub"]
	var mix: float = harmonic_mix

	var dead: Array = []
	for i in range(to_fill):
		var sample: float = 0.0

		for voice in _voices:
			voice["elapsed"] += dt
			var t: float = voice["elapsed"]
			if t < 0.0:
				continue
			if t >= voice["dur"]:
				dead.append(voice)
				continue

			# Full ADSR envelope
			var atk: float     = voice["attack"]
			var dcy: float     = voice["decay"]
			var sus: float     = voice["sustain"]
			var rel: float     = voice["release"]
			var remaining: float = voice["dur"] - t
			var env: float
			if t < atk:
				env = t / atk
			elif t < atk + dcy:
				env = lerpf(1.0, sus, (t - atk) / dcy)
			elif remaining < rel:
				env = sus * (remaining / rel)
			else:
				env = sus

			# Per-instrument additive synthesis (fundamental + 6 overtones + sub)
			var ph: float = voice["phase"]
			var ve: float = voice["vel"] * env
			sample += sin(ph)        * ih[0]       * ve
			sample += sin(ph * 2.0)  * ih[1] * mix * ve
			sample += sin(ph * 3.0)  * ih[2] * mix * ve
			sample += sin(ph * 4.0)  * ih[3] * mix * ve
			sample += sin(ph * 5.0)  * ih[4] * mix * ve
			sample += sin(ph * 6.0)  * ih[5] * mix * ve
			sample += sin(ph * 7.0)  * ih[6] * mix * ve
			sample += sin(ph * 0.5)  * isub  * mix * ve

			voice["phase"] = fmod(voice["phase"] + voice["freq"] * dt * TAU, TAU)

		# Remove dead voices and update active note set
		for v in dead:
			_decrement_active(v.get("midi", -1))
			_voices.erase(v)
		dead.clear()

		sample = clampf(sample * 0.18, -1.0, 1.0)
		_playback.push_frame(Vector2(sample, sample))
