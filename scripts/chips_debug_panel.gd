class_name ChipsDebugPanel
extends CanvasLayer

## Right-side debug/settings panel (380 px wide) for the "Chips From Audio" mode.
## Sections: audio file controls, frequency visualiser, analyser settings,
##           spawn settings, affinity presets and per-interval sliders.

const PANEL_W: float = 380.0

## Western interval names indexed by semitone (0–11).
const INTERVAL_NAMES: Array = ["P1", "m2", "M2", "m3", "M3", "P4", "TT", "P5", "m6", "M6", "m7", "M7"]

## Default affinity preset (theory-based consonance/dissonance).
const DEFAULT_AFFINITY: Array = [1.0, -0.8, -0.2, 0.6, 0.8, 0.5, -0.9, 0.9, 0.4, 0.6, -0.1, -0.7]

signal back_requested
signal file_open_requested
signal play_requested
signal stop_requested
signal spawn_note_requested(pitch: int)

var _analyzer:     ChipsAudioAnalyzer
var _chips_grid:   ChipsLifeGrid
var _audio_engine: AudioEngine   # for notes volume control

# ── UI element references ────────────────────────────────────────────────────
var _file_label:          Label
var _play_btn:            Button
var _progress_bar:        ProgressBar
var _track_vol_slider:    HSlider
var _notes_vol_slider:    HSlider
var _threshold_slider:    HSlider
var _smoothing_slider:    HSlider
var _spawn_thresh_slider: HSlider
var _spawn_rate_slider:   HSlider
var _auto_cons_slider:    HSlider
var _aff_strength_slider: HSlider
var _aff_sliders:         Array = []   # 12 HSliders (one per interval)
var _freq_viz:            ChipsFreqViz
var _note_btns:           Array = []   # 12 Buttons for manual spawn (circle-of-fifths order)


# ────────────────────────────────────────────────────────────────────────────
#  Public API
# ────────────────────────────────────────────────────────────────────────────

## Call after adding to the scene tree. Wires references, then builds UI.
func setup(analyzer: ChipsAudioAnalyzer, chips_grid: ChipsLifeGrid, audio_engine: AudioEngine) -> void:
	_analyzer     = analyzer
	_chips_grid   = chips_grid
	_audio_engine = audio_engine
	layer = 10
	_build_ui()


# ────────────────────────────────────────────────────────────────────────────
#  UI construction
# ────────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Root control anchored to the right edge of the viewport.
	var root := Control.new()
	root.anchor_left   = 1.0
	root.anchor_right  = 1.0
	root.anchor_top    = 0.0
	root.anchor_bottom = 1.0
	root.offset_left   = -PANEL_W
	root.offset_right  = 0.0
	root.offset_top    = 44.0   # leave room for the top bar
	root.offset_bottom = 0.0
	add_child(root)

	# Semi-transparent dark background.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.04, 0.07, 0.97)
	root.add_child(bg)

	# Scroll container fills the root.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	# Build each section.
	_build_header(vbox)
	_build_audio(vbox)
	_build_freq_viz(vbox)
	_build_volume(vbox)
	_build_analyzer(vbox)
	_build_spawn(vbox)
	_build_manual_spawn(vbox)
	_build_affinity(vbox)

	# Bottom spacer so content is not clipped.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer)


# ── Header ───────────────────────────────────────────────────────────────────

func _build_header(vbox: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(hbox)

	var back_btn := Button.new()
	back_btn.text = "← Назад"
	back_btn.custom_minimum_size = Vector2(80, 28)
	back_btn.pressed.connect(func() -> void: back_requested.emit())
	hbox.add_child(back_btn)

	var title := Label.new()
	title.text = "🎮 Chips From Audio"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 13)
	hbox.add_child(title)


# ── Audio section ─────────────────────────────────────────────────────────────

func _build_audio(vbox: VBoxContainer) -> void:
	_make_section_label(vbox, "── АУДІО ──")

	# File row
	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 4)
	vbox.add_child(file_row)

	_file_label = Label.new()
	_file_label.text = "— файл не обрано —"
	_file_label.clip_text = true
	_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_label.add_theme_font_size_override("font_size", 10)
	file_row.add_child(_file_label)

	var open_btn := Button.new()
	open_btn.text = "📂 Відкрити"
	open_btn.pressed.connect(func() -> void: file_open_requested.emit())
	file_row.add_child(open_btn)

	# Playback row
	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 4)
	vbox.add_child(play_row)

	_play_btn = Button.new()
	_play_btn.text = "▶ Грати"
	_play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_btn.pressed.connect(func() -> void: play_requested.emit())
	play_row.add_child(_play_btn)

	var stop_btn := Button.new()
	stop_btn.text = "■ Стоп"
	stop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_btn.pressed.connect(func() -> void: stop_requested.emit())
	play_row.add_child(stop_btn)

	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.custom_minimum_size = Vector2(0, 10)
	_progress_bar.show_percentage = false
	vbox.add_child(_progress_bar)


# ── Frequency visualiser ──────────────────────────────────────────────────────

func _build_freq_viz(vbox: VBoxContainer) -> void:
	_make_section_label(vbox, "── ЧАСТОТИ ──")

	_freq_viz = ChipsFreqViz.new()
	_freq_viz.custom_minimum_size = Vector2(0, 60)
	_freq_viz.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_freq_viz)


# ── Volume section ────────────────────────────────────────────────────────────

func _build_volume(vbox: VBoxContainer) -> void:
	_make_section_label(vbox, "── ГУЧНІСТЬ ──")

	_track_vol_slider = _make_slider_row(vbox, "Трек (дБ)", -40.0, 6.0, 0.0, 0.5)
	_track_vol_slider.value_changed.connect(func(v: float) -> void:
		if _analyzer and _analyzer.player:
			_analyzer.player.volume_db = v
	)

	_notes_vol_slider = _make_slider_row(vbox, "Ноти (0–1)", 0.0, 1.0, 0.7, 0.02)
	_notes_vol_slider.value_changed.connect(func(v: float) -> void:
		if _audio_engine:
			_audio_engine.master_volume = v
	)


# ── Analyser settings ─────────────────────────────────────────────────────────

func _build_analyzer(vbox: VBoxContainer) -> void:
	_make_section_label(vbox, "── АНАЛІЗАТОР ──")

	_threshold_slider = _make_slider_row(vbox, "Поріг dB", -80.0, -10.0, -50.0, 1.0)
	_threshold_slider.value_changed.connect(func(v: float) -> void:
		if _analyzer:
			_analyzer.threshold_db = v
	)

	_smoothing_slider = _make_slider_row(vbox, "Згладжування", 0.0, 0.99, 0.8, 0.01)
	_smoothing_slider.value_changed.connect(func(v: float) -> void:
		if _analyzer:
			_analyzer.smoothing = v
	)


# ── Spawn settings ────────────────────────────────────────────────────────────

func _build_spawn(vbox: VBoxContainer) -> void:
	_make_section_label(vbox, "── СПАВН ──")

	_spawn_thresh_slider = _make_slider_row(vbox, "Мін.енергія", 0.0, 1.0, 0.15, 0.01)
	_spawn_rate_slider   = _make_slider_row(vbox, "Клітин/ноту",  1.0, 8.0, 2.0,  1.0)


# ── Manual spawn ─────────────────────────────────────────────────────────────

func _build_manual_spawn(vbox: VBoxContainer) -> void:
	_make_section_label(vbox, "── РУЧНИЙ СПАВН ──")

	# Info label
	var info := Label.new()
	info.text = "Кольори = консонанс з домінантою"
	info.add_theme_font_size_override("font_size", 9)
	info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(info)

	# 12 note buttons in circle-of-fifths order (same as grid columns)
	# COL_ORDER: C G D A E B F# Db Ab Eb Bb F
	var col_note_names: Array = ["C", "G", "D", "A", "E", "B", "F#", "Db", "Ab", "Eb", "Bb", "F"]
	# COL_ORDER pitches: [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]
	var col_pitches: Array = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]

	var grid_container := GridContainer.new()
	grid_container.columns = 6
	grid_container.add_theme_constant_override("h_separation", 3)
	grid_container.add_theme_constant_override("v_separation", 3)
	vbox.add_child(grid_container)

	_note_btns = []
	for i in 12:
		var btn := Button.new()
		btn.text = col_note_names[i]
		btn.custom_minimum_size = Vector2(50, 28)
		btn.add_theme_font_size_override("font_size", 11)
		var pitch_val: int = col_pitches[i]
		btn.pressed.connect(func() -> void: spawn_note_requested.emit(pitch_val))
		grid_container.add_child(btn)
		_note_btns.append(btn)

	# Auto-consonant spawn strength
	_auto_cons_slider = _make_slider_row(vbox, "Авто-консонанс", 0.0, 1.0, 0.0, 0.05)


# ── Affinity settings ─────────────────────────────────────────────────────────

func _build_affinity(vbox: VBoxContainer) -> void:
	_make_section_label(vbox, "── СПОРІДНЕНІСТЬ ──")

	_aff_strength_slider = _make_slider_row(vbox, "Сила", 0.0, 1.0, 0.5, 0.05)
	_aff_strength_slider.value_changed.connect(func(v: float) -> void:
		if _chips_grid:
			_chips_grid.affinity_strength = v
	)

	# Preset buttons
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 3)
	vbox.add_child(preset_row)

	var btn_theory := Button.new()
	btn_theory.text = "Теорія"
	btn_theory.pressed.connect(func() -> void: _apply_preset(DEFAULT_AFFINITY))
	preset_row.add_child(btn_theory)

	var btn_pent := Button.new()
	btn_pent.text = "Пентатон"
	btn_pent.pressed.connect(func() -> void:
		_apply_preset([-0.3, -0.9, 0.7, -0.5, 0.8, -0.2, -0.9, 0.9, -0.3, 0.7, -0.5, -0.9])
	)
	preset_row.add_child(btn_pent)

	var btn_all_pos := Button.new()
	btn_all_pos.text = "Всі +"
	btn_all_pos.pressed.connect(func() -> void:
		var pos: Array = []
		for _i in 12:
			pos.append(1.0)
		_apply_preset(pos)
	)
	preset_row.add_child(btn_all_pos)

	var btn_all_neg := Button.new()
	btn_all_neg.text = "Всі -"
	btn_all_neg.pressed.connect(func() -> void:
		var neg: Array = []
		for _i in 12:
			neg.append(-1.0)
		_apply_preset(neg)
	)
	preset_row.add_child(btn_all_neg)

	var btn_rand := Button.new()
	btn_rand.text = "Рандом"
	btn_rand.pressed.connect(func() -> void:
		var rnd: Array = []
		for _i in 12:
			rnd.append(randf_range(-1.0, 1.0))
		_apply_preset(rnd)
	)
	preset_row.add_child(btn_rand)

	# Per-interval sliders
	var intervals_lbl := Label.new()
	intervals_lbl.text = "  Інтервали:"
	intervals_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(intervals_lbl)

	_aff_sliders = []
	for i in 12:
		var sl := _make_slider_row(vbox, INTERVAL_NAMES[i], -1.0, 1.0, DEFAULT_AFFINITY[i], 0.05)
		# Capture i by value using a helper closure.
		var idx: int = i
		sl.value_changed.connect(func(v: float) -> void:
			_on_interval_changed(idx, v)
		)
		_aff_sliders.append(sl)


# ────────────────────────────────────────────────────────────────────────────
#  Affinity helpers
# ────────────────────────────────────────────────────────────────────────────

## Update the affinity matrix symmetrically for all roots at a given interval.
func _on_interval_changed(interval: int, value: float) -> void:
	if _chips_grid == null:
		return
	for i in 12:
		var j_fwd: int = (i + interval) % 12
		_chips_grid.affinity[i][j_fwd] = value
		var j_rev: int = (i - interval + 12) % 12
		_chips_grid.affinity[i][j_rev] = value


## Set all 12 interval sliders to the supplied values (triggers _on_interval_changed).
func _apply_preset(values: Array) -> void:
	for i in 12:
		if i < _aff_sliders.size():
			(_aff_sliders[i] as HSlider).value = values[i]


# ────────────────────────────────────────────────────────────────────────────
#  Public update methods (called each frame by the owning scene)
# ────────────────────────────────────────────────────────────────────────────

## Recolour the 12 manual-spawn buttons based on their consonance with the
## current dominant pitch. Green=consonant, grey=neutral, red=dissonant.
func update_consonance_display(dominant_pitch: int, affinity: Array) -> void:
	if _note_btns.is_empty() or affinity.is_empty():
		return
	# Button i corresponds to COL_ORDER[i] pitch class
	var col_pitches: Array = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]
	for i in 12:
		var btn := _note_btns[i] as Button
		if btn == null:
			continue
		var pitch: int = col_pitches[i]
		var aff: float = affinity[dominant_pitch][pitch] if dominant_pitch < affinity.size() else 0.0
		var col: Color
		if aff > 0.4:
			# Green tint — consonant
			col = Color(0.15, 0.55 + aff * 0.3, 0.15)
		elif aff < -0.4:
			# Red tint — dissonant
			col = Color(0.55 + abs(aff) * 0.25, 0.12, 0.12)
		else:
			# Neutral grey
			col = Color(0.25, 0.25, 0.28)
		var style := StyleBoxFlat.new()
		style.bg_color = col
		style.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", style)


## Forward energy data to the frequency visualiser.
func update_freq_display(energy_data: Array) -> void:
	if _freq_viz != null:
		_freq_viz.update_energies(energy_data)


## Update the progress bar (pos / length, both in seconds).
func update_progress(pos: float, length: float) -> void:
	if _progress_bar != null and length > 0.0:
		_progress_bar.value = pos / length


## Update the file label text (e.g. after loading a file).
func set_file_label(text: String) -> void:
	if _file_label != null:
		_file_label.text = text


# ────────────────────────────────────────────────────────────────────────────
#  Spawn parameter accessors
# ────────────────────────────────────────────────────────────────────────────

func get_spawn_threshold() -> float:
	return _spawn_thresh_slider.value if _spawn_thresh_slider != null else 0.15


func get_spawn_rate() -> int:
	return int(_spawn_rate_slider.value) if _spawn_rate_slider != null else 2


func get_auto_consonant_strength() -> float:
	return _auto_cons_slider.value if _auto_cons_slider != null else 0.0


# ────────────────────────────────────────────────────────────────────────────
#  UI builder helpers
# ────────────────────────────────────────────────────────────────────────────

func _make_section_label(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	parent.add_child(lbl)


## Creates an HBoxContainer with label, slider, and live value label.
## Returns the HSlider so callers can connect value_changed.
func _make_slider_row(parent: VBoxContainer, label_text: String,
		min_v: float, max_v: float, value: float, step: float) -> HSlider:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	parent.add_child(hbox)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	hbox.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.value = value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % snappedf(value, step)
	val_lbl.custom_minimum_size = Vector2(40, 0)
	val_lbl.add_theme_font_size_override("font_size", 10)
	hbox.add_child(val_lbl)

	# Keep the value label in sync.
	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = "%.2f" % snappedf(v, step)
	)

	return slider
