class_name DNANote

## One note in a cell's melodic genome.
## pitch: scale degree 0-11
## duration: sixteenth-note units 1-8
## velocity: 0-127
## articulation: 0=legato 1=staccato 2=tenuto 3=accent

var pitch: int = 0
var duration: int = 4
var velocity: int = 80
var articulation: int = 0


static func create(p: int, d: int, v: int, a: int) -> DNANote:
	var n := DNANote.new()
	n.pitch = p
	n.duration = d
	n.velocity = v
	n.articulation = a
	return n


static func random_note(scale_len: int) -> DNANote:
	return create(
		randi() % scale_len,
		randi_range(1, 8),
		randi_range(40, 120),
		randi() % 4
	)


func copy() -> DNANote:
	return DNANote.create(pitch, duration, velocity, articulation)


## Mutate in place based on mutation_rate (0-1) and current scale length.
func mutate(rate: float, scale_len: int) -> void:
	if randf() < rate:
		pitch = (pitch + randi_range(-2, 2) + scale_len * 10) % scale_len
	if randf() < rate * 0.5:
		duration = clampi(duration + randi_range(-1, 1), 1, 8)
	if randf() < rate * 0.3:
		velocity = clampi(velocity + randi_range(-15, 15), 20, 127)
	if randf() < rate * 0.2:
		articulation = randi() % 4


## Drift pitch by ±1 (for old cells).
func age_drift(scale_len: int) -> void:
	if randf() < 0.12:
		pitch = (pitch + randi_range(-1, 1) + scale_len * 10) % scale_len


func to_dict() -> Dictionary:
	return {
		"pitch": pitch,
		"duration": duration,
		"velocity": velocity,
		"articulation": articulation
	}


static func from_dict(d: Dictionary) -> DNANote:
	return create(
		d.get("pitch", 0),
		d.get("duration", 4),
		d.get("velocity", 80),
		d.get("articulation", 0)
	)
