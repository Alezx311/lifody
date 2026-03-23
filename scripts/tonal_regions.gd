class_name TonalRegions
extends Node

## Manages harmonic tonal regions.
## MAP_STANDARD — configurable grid using any of 12 notes × 11 scale types (132 combinations)
## MAP_ISLAND   — empty grid with 12 note islands + custom paintable zones

const MAP_STANDARD: int = 0
const MAP_ISLAND:   int = 1

const NOTE_NAMES: Array = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]

## 12 colors for chromatic pitches (hue wheel).
const NOTE_COLORS: Array = [
	Color(0.95, 0.20, 0.20),  # C  — red
	Color(0.95, 0.50, 0.10),  # C# — orange
	Color(0.95, 0.82, 0.05),  # D  — amber
	Color(0.55, 0.92, 0.05),  # D# — yellow-green
	Color(0.08, 0.88, 0.20),  # E  — green
	Color(0.05, 0.88, 0.68),  # F  — teal
	Color(0.05, 0.62, 0.92),  # F# — sky blue
	Color(0.12, 0.28, 0.95),  # G  — blue
	Color(0.45, 0.12, 0.95),  # G# — indigo
	Color(0.72, 0.10, 0.92),  # A  — purple
	Color(0.92, 0.10, 0.65),  # A# — magenta
	Color(0.92, 0.12, 0.35),  # B  — crimson
]

## 11 scale types (indices 0–10). region_id = root * SCALE_COUNT + scale_idx.
const SCALE_COUNT: int = 11
const SCALE_TYPES: Array = [
	{"name": "Major",       "abbr": "Maj", "intervals": [0,2,4,5,7,9,11]},       # 0
	{"name": "Nat.Minor",   "abbr": "Min", "intervals": [0,2,3,5,7,8,10]},       # 1
	{"name": "Dorian",      "abbr": "Dor", "intervals": [0,2,3,5,7,9,10]},       # 2
	{"name": "Phrygian",    "abbr": "Phr", "intervals": [0,1,3,5,7,8,10]},       # 3
	{"name": "Lydian",      "abbr": "Lyd", "intervals": [0,2,4,6,7,9,11]},       # 4
	{"name": "Mixolydian",  "abbr": "Mix", "intervals": [0,2,4,5,7,9,10]},       # 5
	{"name": "Locrian",     "abbr": "Loc", "intervals": [0,1,3,5,6,8,10]},       # 6
	{"name": "Harm.Minor",  "abbr": "HMn", "intervals": [0,2,3,5,7,8,11]},       # 7
	{"name": "Pent.Major",  "abbr": "PMj", "intervals": [0,2,4,7,9]},            # 8
	{"name": "Pent.Minor",  "abbr": "PMn", "intervals": [0,3,5,7,10]},           # 9
	{"name": "Blues",       "abbr": "Bls", "intervals": [0,3,5,6,7,10]},         # 10
]

## Alpha tints per scale type (subtly different visual weight for modes vs exotic scales)
const SCALE_ALPHAS: Array = [0.10, 0.09, 0.09, 0.09, 0.10, 0.09, 0.08, 0.08, 0.07, 0.07, 0.07]

## Chromatic = index 12 * SCALE_COUNT = 132
## Set dynamically after _build_regions() so it always equals _all_regions.size() - 1.
var CHROMATIC_REGION: int = 132

const TRANSITION_WIDTH: int = 3

var grid_w: int = 80
var grid_h: int = 60
var map_mode: int = MAP_STANDARD

## Standard map grid dimensions (configurable via presets)
var std_cols: int = 4
var std_rows: int = 3

## [row][col] → region index in _all_regions
var region_grid: Array = []

## Full dynamic region list (built in _build_regions)
var _all_regions: Array = []

## Per-cell custom painted region (-1 = no paint, use default)
var custom_region_map: Array = []

## Island definitions for MAP_ISLAND mode
var islands: Array = []


# ────────────────────────────────────────────────────────────────────────────
#  Initialisation
# ────────────────────────────────────────────────────────────────────────────

func setup(w: int, h: int) -> void:
	grid_w = w
	grid_h = h
	_build_regions()
	CHROMATIC_REGION = _all_regions.size() - 1
	_init_custom_map()
	_init_islands()
	apply_preset_all_major()


func _build_regions() -> void:
	## Generate all 12 roots × 11 scale types + 1 Chromatic = 133 entries.
	_all_regions = []
	for root in 12:
		for si in SCALE_COUNT:
			var st: Dictionary = SCALE_TYPES[si]
			var nc: Color = NOTE_COLORS[root]
			var col := Color(nc.r, nc.g, nc.b, SCALE_ALPHAS[si])
			_all_regions.append({
				"name":      "%s %s" % [NOTE_NAMES[root], st["abbr"]],
				"full_name": "%s %s" % [NOTE_NAMES[root], st["name"]],
				"root":  root,
				"scale": st["intervals"],
				"color": col,
			})
	# Chromatic always last (index 132)
	_all_regions.append({
		"name": "Chr", "full_name": "Chromatic",
		"root": 0, "scale": [0,1,2,3,4,5,6,7,8,9,10,11],
		"color": Color(0.55, 0.55, 0.55, 0.09),
	})


## Encode (root, scale_type_index) → region index.
func region_idx(root: int, scale_type: int) -> int:
	return root * SCALE_COUNT + scale_type


# ────────────────────────────────────────────────────────────────────────────
#  Map presets
# ────────────────────────────────────────────────────────────────────────────

func apply_preset_all_major() -> void:
	## 4×3 grid: all 12 chromatic roots in Major scale (chromatic order).
	std_cols = 4
	std_rows = 3
	_fill_grid_by_roots([0,1,2,3,4,5,6,7,8,9,10,11], 0)  # scale 0 = Major


func apply_preset_all_minor() -> void:
	## 4×3 grid: all 12 chromatic roots in Natural Minor.
	std_cols = 4
	std_rows = 3
	_fill_grid_by_roots([0,1,2,3,4,5,6,7,8,9,10,11], 1)  # scale 1 = Nat.Minor


func apply_preset_circle_of_5ths() -> void:
	## 4×3 grid: all 12 roots in Major, ordered by circle of 5ths (C G D A E B F# C# Ab Eb Bb F).
	std_cols = 4
	std_rows = 3
	_fill_grid_by_roots([0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5], 0)


func apply_preset_7modes_c() -> void:
	## 4×2 grid: 7 modes of C major (each mode with its natural root) + Chromatic.
	std_cols = 4
	std_rows = 2
	region_grid = [
		[region_idx(0, 0),  region_idx(2, 2),  region_idx(4, 3),  region_idx(5, 4)],  # Ionian Dorian Phrygian Lydian
		[region_idx(7, 5),  region_idx(9, 1),  region_idx(11, 6), CHROMATIC_REGION],  # Mixo Aeolian Locrian Chr
	]


func apply_preset_all_dorian() -> void:
	## 4×3 grid: all 12 roots in Dorian.
	std_cols = 4
	std_rows = 3
	_fill_grid_by_roots([0,1,2,3,4,5,6,7,8,9,10,11], 2)  # scale 2 = Dorian


func apply_preset_classic() -> void:
	## 3×2 grid: original 6 regions (C/G/D Major, A/E Minor, E Phrygian).
	std_cols = 3
	std_rows = 2
	region_grid = [
		[region_idx(0, 0), region_idx(7, 0), region_idx(2, 0)],
		[region_idx(9, 1), region_idx(4, 1), region_idx(4, 3)],
	]


func _fill_grid_by_roots(roots: Array, scale_type: int) -> void:
	region_grid = []
	var i: int = 0
	for r in std_rows:
		var row_arr: Array = []
		for c in std_cols:
			row_arr.append(region_idx(roots[i % roots.size()], scale_type))
			i += 1
		region_grid.append(row_arr)


# ────────────────────────────────────────────────────────────────────────────
#  Island map init
# ────────────────────────────────────────────────────────────────────────────

func _init_custom_map() -> void:
	custom_region_map = []
	for _y in grid_h:
		var row: Array = []
		for _x in grid_w:
			row.append(-1)
		custom_region_map.append(row)


func _init_islands() -> void:
	islands = []
	# White keys: C D E F G A B at y≈44
	var white_xs:    Array = [5,  16, 27, 38, 49, 60, 71]
	var white_notes: Array = [0,  2,  4,  5,  7,  9,  11]
	for i in 7:
		islands.append({"note": white_notes[i], "name": NOTE_NAMES[white_notes[i]],
						"cx": white_xs[i], "cy": 44, "radius": 7})
	# Black keys: C# D# F# G# A# at y≈18
	var black_xs:    Array = [10, 21, 43, 54, 65]
	var black_notes: Array = [1,  3,  6,  8,  10]
	for i in 5:
		islands.append({"note": black_notes[i], "name": NOTE_NAMES[black_notes[i]],
						"cx": black_xs[i], "cy": 18, "radius": 6})


# ────────────────────────────────────────────────────────────────────────────
#  Region queries
# ────────────────────────────────────────────────────────────────────────────

func _in_bounds_t(x: int, y: int) -> bool:
	return x >= 0 and x < grid_w and y >= 0 and y < grid_h


func get_region_id(x: int, y: int) -> int:
	if map_mode == MAP_ISLAND:
		if _in_bounds_t(x, y) and custom_region_map[y][x] >= 0:
			return custom_region_map[y][x]
		return CHROMATIC_REGION
	# Standard mode: locate cell in the configurable grid
	var col: int = clampi(int(float(x) / float(grid_w) * float(std_cols)), 0, std_cols - 1)
	var row: int = clampi(int(float(y) / float(grid_h) * float(std_rows)), 0, std_rows - 1)
	if region_grid.is_empty():
		return CHROMATIC_REGION
	return region_grid[row][col]


func _safe_region(rid: int) -> Dictionary:
	if rid < 0 or rid >= _all_regions.size():
		return _all_regions[CHROMATIC_REGION]
	return _all_regions[rid]


func get_scale(region_id: int) -> Array:
	return _safe_region(region_id)["scale"]


func get_root(region_id: int) -> int:
	return _safe_region(region_id)["root"]


func get_scale_len(region_id: int) -> int:
	return (_safe_region(region_id)["scale"] as Array).size()


func pitch_to_midi(pitch: int, region_id: int, octave_offset: int = 0) -> int:
	var reg: Dictionary = _safe_region(region_id)
	var scale: Array = reg["scale"]
	# Chromatic: pitch maps directly to semitone
	if scale.size() == 12:
		return 60 + octave_offset * 12 + pitch % 12
	var semitone: int = scale[pitch % scale.size()]
	var root: int    = reg["root"]
	return 60 + octave_offset * 12 + root + semitone


func get_color(region_id: int) -> Color:
	return _safe_region(region_id)["color"]


func get_note_color(pitch: int) -> Color:
	return NOTE_COLORS[pitch % 12]


func get_region_name(region_id: int) -> String:
	return _safe_region(region_id)["name"]


func get_region_full_name(region_id: int) -> String:
	return _safe_region(region_id).get("full_name", get_region_name(region_id))


# ────────────────────────────────────────────────────────────────────────────
#  Transition zones & painting
# ────────────────────────────────────────────────────────────────────────────

func is_transition(x: int, y: int) -> bool:
	if map_mode == MAP_ISLAND:
		return false
	# Near any cell-boundary in the std_cols × std_rows grid?
	var cell_w: float = float(grid_w) / float(std_cols)
	var cell_h: float = float(grid_h) / float(std_rows)
	var fx: float = fmod(float(x), cell_w)
	var fy: float = fmod(float(y), cell_h)
	var dx: float = minf(fx, cell_w - fx)
	var dy: float = minf(fy, cell_h - fy)
	return dx <= float(TRANSITION_WIDTH) or dy <= float(TRANSITION_WIDTH)


## Paint tonal region onto custom map with a circular brush.
## region_id = -1 erases the paint. Zones can overlap — last painted wins.
func paint_region(cx: int, cy: int, radius: int, region_id: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var px: int = cx + dx
				var py: int = cy + dy
				if _in_bounds_t(px, py):
					custom_region_map[py][px] = region_id


func clear_custom_map() -> void:
	_init_custom_map()


# ────────────────────────────────────────────────────────────────────────────
#  Legacy boundary helpers (kept for API compat, no longer drive std rendering)
# ────────────────────────────────────────────────────────────────────────────

func boundary_px_x(_idx: int) -> float:
	return 0.0

func boundary_px_y() -> float:
	return 0.0

func drag_boundary_x(_idx: int, _delta_norm: float) -> void:
	pass

func drag_boundary_y(_delta_norm: float) -> void:
	pass
