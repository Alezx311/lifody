class_name SampleBank
extends Node

## Loads .ogg sample files for 8 instruments from res://samples/.
## For any target MIDI note, finds the nearest recorded pitch and
## returns the stream + pitch_scale needed to transpose it exactly.

## Instrument index → subfolder name (matches AudioEngine preset order)
const FOLDERS: Array = [
	"guitar-nylon",   # 0 Synth
	"piano",          # 1 Piano
	"organ",          # 2 Organ
	"cello",          # 3 Strings
	"guitar-acoustic",# 4 Bell
	"saxophone",      # 5 Flute/Wind
	"bass-electric",  # 6 Bass
	"violin",         # 7 Pad
]

## Note name string → semitone offset (0–11)
const NOTE_MAP: Dictionary = {
	"C": 0, "Cs": 1, "D": 2, "Ds": 3, "E": 4, "F": 5,
	"Fs": 6, "G": 7, "Gs": 8, "A": 9, "As": 10, "B": 11
}

## Semitone index → note name stem (inverse of NOTE_MAP, sharps only)
const NOTE_NAMES_SHARP: Array = ["C","Cs","D","Ds","E","F","Fs","G","Gs","A","As","B"]

## _banks[inst_idx] = Dictionary{ midi_int: AudioStream }
var _banks: Array = []
## _keys[inst_idx] = sorted Array[int] of available MIDI notes
var _keys: Array = []

var is_loaded: bool = false


func load_all() -> void:
	_banks.clear()
	_keys.clear()
	for folder in FOLDERS:
		var bank: Dictionary = {}
		var dir_path: String = "res://samples/" + folder
		# Enumerate known MIDI range instead of using DirAccess, which is
		# unreliable on the PCK virtual filesystem in exported Godot 4 builds.
		for midi in range(21, 109):  # A0 (21) – C8 (108), standard piano range
			var path: String = dir_path + "/" + _midi_to_fname(midi) + ".ogg"
			if ResourceLoader.exists(path):
				var stream = ResourceLoader.load(path)
				if stream != null:
					bank[midi] = stream
		if bank.is_empty():
			push_warning("SampleBank: no samples loaded for " + folder)
		_banks.append(bank)
		var keys: Array = bank.keys()
		keys.sort()
		_keys.append(keys)
	is_loaded = true


## Returns {stream, pitch_scale} for instrument + target MIDI.
## pitch_scale transposes the nearest recorded note to the exact target pitch.
func get_sample(inst_idx: int, target_midi: int) -> Dictionary:
	if inst_idx < 0 or inst_idx >= _banks.size():
		return {}
	var bank: Dictionary = _banks[inst_idx]
	var keys: Array = _keys[inst_idx]
	if keys.is_empty():
		return {}
	# Binary-search nearest
	var nearest: int = keys[0]
	var lo: int = 0
	var hi: int = keys.size() - 1
	while lo <= hi:
		var mid: int = (lo + hi) / 2
		var k: int = keys[mid]
		if abs(k - target_midi) < abs(nearest - target_midi):
			nearest = k
		if k < target_midi:
			lo = mid + 1
		elif k > target_midi:
			hi = mid - 1
		else:
			nearest = k
			break
	var pitch_scale: float = pow(2.0, float(target_midi - nearest) / 12.0)
	return {"stream": bank[nearest], "pitch_scale": pitch_scale}


## Convert MIDI number to filename stem, e.g. 69 → "A4".
## Inverse of _parse_midi(); uses sharp names to match the sample filenames.
func _midi_to_fname(midi: int) -> String:
	var semitone: int = (midi - 12) % 12
	var octave: int   = (midi - 12) / 12
	return NOTE_NAMES_SHARP[semitone] + str(octave)


## Parse "A4", "As4", "Cs3" → MIDI number. Returns -1 on failure.
func _parse_midi(stem: String) -> int:
	var i: int = 0
	var note_str: String = ""
	# Collect letter(s): first char uppercase letter, optional second 's'
	if i < stem.length() and stem[i] >= "A" and stem[i] <= "G":
		note_str += stem[i]
		i += 1
	else:
		return -1
	if i < stem.length() and stem[i] == "s":
		note_str += "s"
		i += 1
	# Rest must be a valid integer (octave)
	var oct_str: String = stem.substr(i)
	if not oct_str.is_valid_int():
		return -1
	var octave: int = int(oct_str)
	if not NOTE_MAP.has(note_str):
		return -1
	# MIDI: C4 = 60 → C0 = 12, so midi = 12 + octave*12 + semitone
	return 12 + octave * 12 + NOTE_MAP[note_str]
