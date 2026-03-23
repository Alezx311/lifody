class_name CellState

## State of a single grid cell.
## Not a Node — pure data object.

var alive: bool = false
var genome: Array = []   # Array[DNANote]
var age: int = 0
var tonal_region: int = 0
var frozen: bool = false


static func create_alive(genome_arr: Array) -> CellState:
	var s := CellState.new()
	s.alive = true
	s.genome = genome_arr
	return s


func copy() -> CellState:
	var s := CellState.new()
	s.alive = alive
	s.age = age
	s.tonal_region = tonal_region
	s.frozen = frozen
	for note in genome:
		s.genome.append((note as DNANote).copy())
	return s


## Create a new cell via genetic crossover of parent cells.
## parents: Array[CellState], mutation_rate: float, scale_len: int
static func crossover(parents: Array, mutation_rate: float, region_id: int, scale_len: int) -> CellState:
	if parents.is_empty():
		return CellState.new()

	# Oldest two parents are dominant
	var sorted := parents.duplicate()
	sorted.sort_custom(func(a: CellState, b: CellState) -> bool:
		return a.age > b.age
	)

	var dom: CellState = sorted[0]
	var genome_len: int = dom.genome.size()
	var new_genome: Array = []

	for i in range(genome_len):
		var parent: CellState = sorted[randi() % mini(2, sorted.size())]
		var note: DNANote
		if i < parent.genome.size():
			note = (parent.genome[i] as DNANote).copy()
		else:
			note = DNANote.random_note(scale_len)
		note.mutate(mutation_rate, scale_len)
		new_genome.append(note)

	var s := CellState.new()
	s.alive = true
	s.genome = new_genome
	s.tonal_region = region_id
	return s
