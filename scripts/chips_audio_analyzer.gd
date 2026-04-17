class_name ChipsAudioAnalyzer
extends Node

## AudioEffectSpectrumAnalyzer wrapper for the "Chips From Audio" mode.
## Creates a dedicated "ChipsAnalysis" audio bus, routes an AudioStreamPlayer
## through it, and exposes per-note energy data across configurable octaves.

const BUS_NAME: String = "ChipsAnalysis"

## Lerp factor applied each analyze() call (higher = more smoothing).
var smoothing: float = 0.8
## dB floor; magnitudes below this are treated as zero energy.
var threshold_db: float = -50.0
## Lowest octave to analyse (C2 = MIDI 36).
var octave_min: int = 2
## Highest octave to analyse (C8 = MIDI 108).
var octave_max: int = 8

# ── Internal ─────────────────────────────────────────────────────────────────
var player: AudioStreamPlayer
var _bus_idx: int = -1
var _analyzer_inst  # AudioEffectSpectrumAnalyzerInstance — untyped on purpose
var _smooth_data: Array = []  # [oct_count][12] smoothed energies (float)

signal audio_ended
signal file_loaded(path: String)


# ────────────────────────────────────────────────────────────────────────────
#  Lifecycle
# ────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_setup_bus()
	player = AudioStreamPlayer.new()
	player.bus = BUS_NAME
	add_child(player)
	player.finished.connect(func() -> void: audio_ended.emit())
	_reset_smooth()


# ────────────────────────────────────────────────────────────────────────────
#  Bus / analyser setup
# ────────────────────────────────────────────────────────────────────────────

func _setup_bus() -> void:
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx == -1:
		AudioServer.add_bus()
		_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
		AudioServer.set_bus_send(_bus_idx, "Master")
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		fx.buffer_length = 0.1
		AudioServer.add_bus_effect(_bus_idx, fx, 0)
	_refresh_instance()


func _refresh_instance() -> void:
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx == -1:
		return
	if AudioServer.get_bus_effect_count(_bus_idx) > 0:
		_analyzer_inst = AudioServer.get_bus_effect_instance(_bus_idx, 0)


# ────────────────────────────────────────────────────────────────────────────
#  Helpers
# ────────────────────────────────────────────────────────────────────────────

func _octave_count() -> int:
	return octave_max - octave_min + 1


func _reset_smooth() -> void:
	_smooth_data = []
	for _o in _octave_count():
		var row: Array = []
		for _n in 12:
			row.append(0.0)
		_smooth_data.append(row)


# ────────────────────────────────────────────────────────────────────────────
#  File loading & playback
# ────────────────────────────────────────────────────────────────────────────

func load_file(path: String) -> bool:
	var stream = null
	var ext: String = path.get_extension().to_lower()
	if ext == "ogg":
		stream = AudioStreamOggVorbis.load_from_file(path)
	elif ext == "mp3":
		stream = AudioStreamMP3.load_from_file(path)
	else:
		push_warning("ChipsAudioAnalyzer: unsupported format '%s'" % ext)
		return false

	if stream == null:
		push_warning("ChipsAudioAnalyzer: failed to load '%s'" % path)
		return false

	player.stream = stream
	_reset_smooth()
	file_loaded.emit(path)
	return true


func play() -> void:
	if player.stream != null and not player.playing:
		player.play()


func stop() -> void:
	player.stop()


func is_playing() -> bool:
	return player.playing


func get_position() -> float:
	return player.get_playback_position()


func get_length() -> float:
	if player.stream != null:
		return player.stream.get_length()
	return 0.0


func seek(pos: float) -> void:
	if player.playing:
		player.seek(pos)


# ────────────────────────────────────────────────────────────────────────────
#  Spectrum analysis
# ────────────────────────────────────────────────────────────────────────────

## Returns a 2-D Array [octave_count][12] of smoothed energy values (0..1).
func analyze() -> Array:
	if _analyzer_inst == null:
		_refresh_instance()
		if _analyzer_inst == null:
			return _smooth_data.duplicate(true)

	var result: Array = []
	for o in _octave_count():
		var row: Array = []
		var octave: int = octave_min + o
		for n in 12:
			# MIDI note: C4 = 60 = 12*(4+1)+0
			var midi: int = 12 * (octave + 1) + n
			var freq_lo: float = 440.0 * pow(2.0, (float(midi) - 0.5 - 69.0) / 12.0)
			var freq_hi: float = 440.0 * pow(2.0, (float(midi) + 0.5 - 69.0) / 12.0)
			var mag: Vector2 = _analyzer_inst.get_magnitude_for_frequency_range(
				freq_lo, freq_hi,
				AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX
			)
			var db_val: float = linear_to_db(maxf(mag.x, mag.y))
			# Normalise to 0..1 relative to threshold floor
			var energy: float = clampf((db_val - threshold_db) / (-threshold_db), 0.0, 1.0)
			# Smooth
			_smooth_data[o][n] = lerp(_smooth_data[o][n], energy, 1.0 - smoothing)
			row.append(_smooth_data[o][n])
		result.append(row)
	return result
