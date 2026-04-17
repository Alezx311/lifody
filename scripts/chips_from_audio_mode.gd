class_name ChipsFromAudioMode
extends Node2D

## "Chips From Audio" game mode.
## Audio file → spectrum analysis → cells spawn on a Circle-of-Fifths grid
## → evolve via Conway rules + note-affinity system.
##
## Grid layout (Circle of Fifths):
##   columns 0–11 = C G D A E B F# Db Ab Eb Bb F  (each column = a P5 from its neighbour)
##   rows    0–4  = octaves 3–7

const NOTES_COLS:   int = 12
const OCTAVES_ROWS: int = 5
const OCTAVE_MIN:   int = 3   # C3 … C7

signal back_requested

var _analyzer:     ChipsAudioAnalyzer
var _grid:         ChipsLifeGrid
var _cluster_mgr:  ClusterManager
var _audio_engine: AudioEngine
var _tonal:        TonalRegions
var _debug_panel:  ChipsDebugPanel
var _file_dialog:  FileDialog

var _cell_size:      int = 60
var _latest_energy:  Array = []   # last analyze() result
var _dominant_pitch: int = 0      # pitch class with highest energy this frame


# ────────────────────────────────────────────────────────────────────────────
#  Entry point (called by main.gd after add_child)
# ────────────────────────────────────────────────────────────────────────────

func setup(vp_size: Vector2) -> void:
	_compute_cell_size(vp_size)
	_create_systems()
	_wire_signals()
	_create_file_dialog()


func _compute_cell_size(vp: Vector2) -> void:
	var available_w: float = vp.x - ChipsDebugPanel.PANEL_W - 60.0
	var available_h: float = vp.y - 44.0 - 30.0
	_cell_size = clampi(int(minf(available_w / NOTES_COLS, available_h / OCTAVES_ROWS)), 30, 120)


func _create_systems() -> void:
	# 1. Analyser
	_analyzer = ChipsAudioAnalyzer.new()
	_analyzer.octave_min = OCTAVE_MIN
	_analyzer.octave_max = OCTAVE_MIN + OCTAVES_ROWS - 1
	add_child(_analyzer)

	# 2. Tonal regions — MAP_ISLAND (no custom zones) → all cells → CHROMATIC_REGION
	#    pitch_to_midi will use: 60 + octave_offset*12 + pitch, giving correct MIDI
	_tonal = TonalRegions.new()
	_tonal.setup(NOTES_COLS, OCTAVES_ROWS)
	_tonal.map_mode = TonalRegions.MAP_ISLAND
	add_child(_tonal)

	# 3. Chips life grid (circle-of-fifths column order)
	_grid = ChipsLifeGrid.new()
	_grid.octave_min = OCTAVE_MIN
	_grid.setup_tonal(_tonal)
	_grid.resize_grid(NOTES_COLS, OCTAVES_ROWS, _cell_size)
	_grid.position = Vector2(60.0, 44.0 + 25.0)
	_grid.running = false
	add_child(_grid)

	# 4. Cluster manager
	_cluster_mgr = ClusterManager.new()
	_cluster_mgr.setup(_grid, _tonal)
	add_child(_cluster_mgr)

	# 5. Audio engine (synthesises cluster melodies)
	_audio_engine = AudioEngine.new()
	_audio_engine.setup_tonal(_tonal)
	_audio_engine.setup_grid(_grid)
	add_child(_audio_engine)

	# 6. Debug panel
	_debug_panel = ChipsDebugPanel.new()
	add_child(_debug_panel)
	_debug_panel.setup(_analyzer, _grid, _audio_engine)


func _wire_signals() -> void:
	_grid.tick_completed.connect(func(tick_num: int) -> void:
		_cluster_mgr.detect_clusters()
		_on_grid_tick(tick_num)
	)
	_cluster_mgr.clusters_updated.connect(_audio_engine.play_clusters)

	_debug_panel.back_requested.connect(func() -> void: back_requested.emit())
	_debug_panel.file_open_requested.connect(_open_file_dialog)
	_debug_panel.play_requested.connect(_on_play_requested)
	_debug_panel.stop_requested.connect(_on_stop_requested)
	_debug_panel.spawn_note_requested.connect(func(pitch: int) -> void:
		_grid.spawn_note_manual(pitch, _debug_panel.get_spawn_rate())
	)

	_analyzer.audio_ended.connect(func() -> void: _grid.running = false)
	_analyzer.file_loaded.connect(func(path: String) -> void:
		_debug_panel.set_file_label(path.get_file())
	)


func _create_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = ["*.ogg ; OGG Vorbis", "*.mp3 ; MP3 Audio"]
	_file_dialog.title = "Завантажити аудіо трек"
	_file_dialog.size = Vector2i(720, 480)
	_file_dialog.file_selected.connect(func(path: String) -> void:
		_analyzer.load_file(path)
	)
	add_child(_file_dialog)


# ────────────────────────────────────────────────────────────────────────────
#  Runtime
# ────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not _analyzer.is_playing():
		return
	_latest_energy = _analyzer.analyze()
	_dominant_pitch = _get_dominant_pitch()
	_debug_panel.update_freq_display(_latest_energy)
	_debug_panel.update_progress(_analyzer.get_position(), _analyzer.get_length())
	_debug_panel.update_consonance_display(_dominant_pitch, _grid.affinity)


func _on_grid_tick(_tick_num: int) -> void:
	if _latest_energy.is_empty():
		return
	var threshold: float = _debug_panel.get_spawn_threshold()
	var rate: int        = _debug_panel.get_spawn_rate()
	_grid.spawn_from_energy(_latest_energy, threshold, rate)

	# Auto-consonant spawn: additionally spawn notes consonant with dominant
	var auto_str: float = _debug_panel.get_auto_consonant_strength()
	if auto_str > 0.01 and _dominant_pitch >= 0:
		for n in 12:
			var aff: float = _grid.affinity[_dominant_pitch][n]
			if aff > 0.4 and randf() < aff * auto_str * 0.5:
				_grid.spawn_note_manual(n, 1)


func _get_dominant_pitch() -> int:
	if _latest_energy.is_empty():
		return 0
	var sums: Array = []
	for _n in 12:
		sums.append(0.0)
	for oct_data in _latest_energy:
		for n in 12:
			sums[n] += float(oct_data[n])
	var best_e := 0.0
	var best_n := 0
	for n in 12:
		if sums[n] > best_e:
			best_e = sums[n]
			best_n = n
	return best_n


func _on_play_requested() -> void:
	_analyzer.play()
	_grid.running = true


func _on_stop_requested() -> void:
	_analyzer.stop()
	_grid.running = false


func _open_file_dialog() -> void:
	_file_dialog.popup_centered()


func stop_all() -> void:
	_analyzer.stop()
	_grid.running = false
