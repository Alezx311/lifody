class_name ChipsFreqViz
extends Control

## Simple frequency-bar visualiser for "Chips From Audio" mode.
## Displays 12 bars (one per pitch class) with note-name labels in the footer.
## Feed data via update_energies() each frame.

const NOTE_NAMES: Array = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

## Current per-pitch-class energy values (0..1), collapsed across octaves.
var energies: Array = []  # 12 floats


# ────────────────────────────────────────────────────────────────────────────
#  Drawing
# ────────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if energies.is_empty():
		return

	var bar_w: float = size.x / 12.0
	var font := ThemeDB.fallback_font

	for i in 12:
		var e: float = energies[i] if i < energies.size() else 0.0

		# Bar height fills the area above the 14-px footer
		var h: float = e * (size.y - 14.0)
		var bar_color: Color = Color.from_hsv(float(i) / 12.0, 0.8, 0.9, 1.0)

		# Filled bar (grows upward from footer)
		draw_rect(
			Rect2(i * bar_w + 0.5, size.y - 14.0 - h, bar_w - 1.0, h),
			bar_color
		)

		# Dark footer strip behind the note label
		draw_rect(
			Rect2(i * bar_w + 0.5, size.y - 13.0, bar_w - 1.0, 13.0),
			Color(0.1, 0.1, 0.12)
		)

		# Note name centred in the footer
		if font != null:
			draw_string(
				font,
				Vector2(i * bar_w + 2.0, size.y - 2.0),
				NOTE_NAMES[i],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				8,
				Color(0.6, 0.6, 0.6)
			)


# ────────────────────────────────────────────────────────────────────────────
#  Data update
# ────────────────────────────────────────────────────────────────────────────

## Collapse multi-octave energy data into 12 per-pitch-class values (max across octaves).
## data: Array[Array[float]] — shape [octave_count][12].
func update_energies(data: Array) -> void:
	energies = []
	for _n in 12:
		energies.append(0.0)

	for oct_data in data:
		for n in 12:
			if n < oct_data.size():
				energies[n] = maxf(energies[n], float(oct_data[n]))

	queue_redraw()
