class_name ChipsLifeGrid
extends LifeGrid

## Extends LifeGrid for "Chips From Audio" mode.
## Grid columns = 12 pitch classes (C..B), rows = octaves.
## Adds a note-affinity system that modifies Conway birth/death:
##   consonant neighbours → affinity-boosted births,
##   dissonant neighbours → affinity-driven extra deaths.

const NOTE_NAMES: Array = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

## Column → pitch class mapping in Circle-of-Fifths order.
## Adjacent columns are a Perfect 5th apart, so the default affinity (P5=0.9)
## makes cells naturally cluster with harmonically close neighbours.
## C  G  D  A  E  B  F# Db Ab Eb Bb F
const COL_ORDER: Array = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]

## Inverse lookup: pitch → column index (built once from COL_ORDER).
var _pitch_to_col: Array = []   # [12] of int

## affinity[i][j] in [-1, 1]: how much pitch-class i "likes" pitch-class j.
## Positive = consonant (birth bonus), negative = dissonant (death penalty).
var affinity: Array = []  # [12][12] of float

## Strength of affinity effect. 0 = disabled, 1 = maximum influence.
var affinity_strength: float = 0.5

## Lowest octave represented by row 0.
var octave_min: int = 2


# ────────────────────────────────────────────────────────────────────────────
#  Initialisation
# ────────────────────────────────────────────────────────────────────────────

func _init() -> void:
	_build_pitch_to_col()
	_build_default_affinity()


func _build_pitch_to_col() -> void:
	_pitch_to_col = []
	for _i in 12:
		_pitch_to_col.append(0)
	for col in 12:
		_pitch_to_col[COL_ORDER[col]] = col


func _build_default_affinity() -> void:
	## Values indexed by interval semitones above root (0–11):
	## P1=unison, m2, M2, m3, M3, P4, TT=tritone, P5, m6, M6, m7, M7
	var by_interval: Array = [1.0, -0.8, -0.2, 0.6, 0.8, 0.5, -0.9, 0.9, 0.4, 0.6, -0.1, -0.7]
	affinity = []
	for i in 12:
		var row: Array = []
		for j in 12:
			row.append(by_interval[(j - i + 12) % 12])
		affinity.append(row)


# ────────────────────────────────────────────────────────────────────────────
#  Coordinate helpers
# ────────────────────────────────────────────────────────────────────────────

func col_to_pitch(x: int) -> int:
	return COL_ORDER[x % 12]


## Returns the column index for a given pitch class (0–11).
func pitch_to_col(pitch: int) -> int:
	return _pitch_to_col[pitch % 12]


func cell_to_midi(x: int, y: int) -> int:
	return 12 * (octave_min + y + 1) + col_to_pitch(x)


# ────────────────────────────────────────────────────────────────────────────
#  Spawning
# ────────────────────────────────────────────────────────────────────────────

func _spawn_cell_at_pitch(x: int, y: int) -> void:
	if not _in_bounds(x, y):
		return
	var pitch: int = col_to_pitch(x)
	var note: DNANote = DNANote.create(pitch, randi_range(1, 4), randi_range(60, 100), 0)
	var genome: Array = [note, note.copy(), note.copy(), note.copy()]
	cells[y][x] = CellState.create_alive(genome)


## Spawn cells driven by external energy data.
## energy_data: Array[Array[float]] — [octave_count][12], values 0..1.
## threshold: minimum energy to trigger a spawn.
## cells_per_note: how many cells to attempt per active note.
func spawn_from_energy(energy_data: Array, threshold: float, cells_per_note: int) -> void:
	var oct_count: int = energy_data.size()
	for o in oct_count:
		var row_data: Array = energy_data[o]
		for n in 12:
			var e: float = row_data[n] if n < row_data.size() else 0.0
			if e < threshold:
				continue
			var gx: int = pitch_to_col(n)   # circle-of-fifths column
			var gy: int = o                   # row = octave index
			if not _in_bounds(gx, gy):
				continue
			for _attempt in cells_per_note:
				var tx: int = clampi(gx + randi_range(-1, 1), 0, GRID_W - 1)
				var ty: int = clampi(gy + randi_range(0, 1), 0, GRID_H - 1)
				if not cells[ty][tx].alive:
					_spawn_cell_at_pitch(tx, ty)
	queue_redraw()


## Manually spawn cells for a specific pitch class across all octave rows.
## octave_row = -1 means spawn across all rows, otherwise only that row.
func spawn_note_manual(pitch: int, cells_per_row: int, octave_row: int = -1) -> void:
	var col: int = pitch_to_col(pitch)
	var row_start: int = 0 if octave_row < 0 else octave_row
	var row_end: int = GRID_H - 1 if octave_row < 0 else octave_row
	for gy in range(row_start, row_end + 1):
		for _s in cells_per_row:
			var tx: int = clampi(col + randi_range(-1, 1), 0, GRID_W - 1)
			var ty: int = clampi(gy + randi_range(0, 1), 0, GRID_H - 1)
			_spawn_cell_at_pitch(tx, ty)
	queue_redraw()


# ────────────────────────────────────────────────────────────────────────────
#  Simulation (overridden generation step with affinity layer)
# ────────────────────────────────────────────────────────────────────────────

func _next_generation() -> Array:
	# Run standard Conway + LifeGrid rules first
	var next: Array = super._next_generation()

	if affinity_strength < 0.01:
		return next

	for y in GRID_H:
		for x in GRID_W:
			var my_pitch: int = col_to_pitch(x)

			# Sum affinity scores from all 8 neighbours (using current `cells`)
			var aff_score: float = 0.0
			var nb_alive: int = 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if _in_bounds(nx, ny) and cells[ny][nx].alive:
						var nb_pitch: int = col_to_pitch(nx)
						aff_score += affinity[my_pitch][nb_pitch]
						nb_alive += 1

			if nb_alive == 0:
				continue

			var avg: float = aff_score / float(nb_alive)

			if not next[y][x].alive:
				# Affinity-driven extra birth: requires consonant neighbourhood
				if avg > 0.6 and nb_alive >= 2 and randf() < avg * affinity_strength * 0.2:
					var alive_nb: Array = _alive_neighbors(x, y)
					if not alive_nb.is_empty():
						next[y][x] = CellState.crossover(alive_nb, base_mutation_rate, 0, 12)
						# Pin all genome notes to this column's pitch class
						for note in next[y][x].genome:
							(note as DNANote).pitch = my_pitch
			else:
				# Affinity-driven extra death: dissonant neighbourhood kills
				if avg < -0.5 and not cells[y][x].frozen and randf() < absf(avg) * affinity_strength * 0.35:
					next[y][x] = CellState.new()

	return next


# ────────────────────────────────────────────────────────────────────────────
#  Rendering
# ────────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	super._draw()

	var font := ThemeDB.fallback_font
	if font == null:
		return

	var font_size: int = maxi(8, int(CELL_SIZE * 0.5))

	# Note names across the top (one per column, 12 columns)
	for x in 12:
		if x >= GRID_W:
			break
		draw_string(
			font,
			Vector2(x * CELL_SIZE + 2.0, -5.0),
			NOTE_NAMES[x],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.85, 0.85, 0.85, 0.7)
		)

	# Octave labels on the left margin
	for y in GRID_H:
		draw_string(
			font,
			Vector2(-24.0, y * CELL_SIZE + CELL_SIZE * 0.75),
			"O" + str(octave_min + y),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size - 1,
			Color(0.7, 0.7, 0.7, 0.6)
		)
