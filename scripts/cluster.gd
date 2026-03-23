class_name Cluster

## A connected group of live cells forming one musical organism.

var id: int = 0
var cells: Array = []         # Array of Vector2i [x,y]
var fitness_score: float = 50.0
var birth_tick: int = 0
var melody: Array = []        # Array[DNANote] — ordered genome for playback
var state: String = "evolving"  # evolving | stable | oscillating | glider
var melody_index: int = 0     # Which note in melody is playing now
var note_ticks_elapsed: float = 0.0


func get_size() -> int:
	return cells.size()


func get_bbox() -> Rect2i:
	if cells.is_empty():
		return Rect2i(0, 0, 0, 0)
	var min_x: int = (cells[0] as Vector2i).x
	var max_x: int = min_x
	var min_y: int = (cells[0] as Vector2i).y
	var max_y: int = min_y
	for c in cells:
		var v := c as Vector2i
		if v.x < min_x: min_x = v.x
		if v.x > max_x: max_x = v.x
		if v.y < min_y: min_y = v.y
		if v.y > max_y: max_y = v.y
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func get_density() -> float:
	var bbox := get_bbox()
	var area: int = bbox.size.x * bbox.size.y
	if area == 0:
		return 1.0
	return float(cells.size()) / float(area)


func get_age(current_tick: int) -> int:
	return current_tick - birth_tick


## Returns the octave offset based on bounding box area (compact = lower).
func get_octave_offset() -> int:
	var bbox := get_bbox()
	var area: int = bbox.size.x * bbox.size.y
	# Small clusters → octave 4, large → octave 5
	if area < 20:
		return -1
	elif area < 100:
		return 0
	else:
		return 1


func get_volume_scale() -> float:
	# Larger cluster = louder
	return clampf(0.2 + float(cells.size()) * 0.03, 0.1, 1.0)


func modify_fitness(delta: float) -> void:
	fitness_score = clampf(fitness_score + delta, 0.0, 100.0)


## Per-tick fitness decay.
func tick_decay() -> void:
	fitness_score = clampf(fitness_score - 0.1, 0.0, 100.0)


func get_survival_bonus() -> float:
	return (fitness_score - 50.0) * 0.005


## Advance the melody playback cursor; returns the note that just started (or null).
func advance_melody(delta_ticks: float, ticks_per_beat: float) -> DNANote:
	if melody.is_empty():
		return null
	note_ticks_elapsed += delta_ticks
	var current_note := melody[melody_index] as DNANote
	var note_ticks: float = float(current_note.duration) * ticks_per_beat / 4.0
	if note_ticks_elapsed >= note_ticks:
		note_ticks_elapsed -= note_ticks
		melody_index = (melody_index + 1) % melody.size()
		return melody[melody_index] as DNANote
	return null


func get_current_note() -> DNANote:
	if melody.is_empty():
		return null
	return melody[melody_index] as DNANote


func to_dict(current_tick: int) -> Dictionary:
	var notes_arr: Array = []
	for n in melody:
		notes_arr.append((n as DNANote).to_dict())
	var bbox := get_bbox()
	return {
		"id": id,
		"size": get_size(),
		"density": get_density(),
		"age": get_age(current_tick),
		"fitness": fitness_score,
		"genome": notes_arr,
		"state": state,
		"octave": get_octave_offset(),
		"volume": get_volume_scale(),
		"bbox": [bbox.position.x, bbox.position.y, bbox.size.x, bbox.size.y]
	}
