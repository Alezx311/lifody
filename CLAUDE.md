# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Lifody is a **Godot 4.6** game combining Conway's Game of Life with musical evolution. Cells carry melodic genomes (DNA), evolve via crossover/mutation, form clusters (organisms), and synthesize music in real time. Players use tools and feedback to steer evolution toward musically interesting states.

## Running the Project

**Pre-built:** Execute `Lifody.exe` directly — no build required.

**From Godot editor:**
1. Open `project.godot` in Godot 4.6+
2. Press **F5** to run

**Export to .exe:** File → Export → Windows Desktop (presets already configured in `export_presets.cfg`)

## Architecture

### System Wiring (main.gd)
`main.gd` (Node2D) bootstraps all subsystems, wires Godot signals between them, and drives the game loop via `tick_completed`:

```
main.gd
 ├── TonalRegions       — Configurable harmonic zones (6 presets, 2 map modes, 11 scale types)
 ├── LifeGrid           — Game of Life simulation + DNA crossover/mutation
 ├── ClusterManager     — BFS clustering to find connected groups (organisms)
 ├── AudioEngine        — Sample-based playback (24-voice pool, look-ahead scheduler)
 │    └── SampleBank    — Loads .ogg samples for 8 instruments from res://samples/
 ├── FitnessManager     — Player feedback scoring, melody library, similarity matching
 ├── ToolManager        — Routes player tool interactions to the grid (11 tools)
 ├── CatalystEvents     — 5 special one-shot events, tick-based token economy
 ├── EvolutionTracker   — Ring buffer (200 ticks) of cell count, avg fitness, milestones
 ├── ChipsAudioAnalyzer — FFT wrapper (AudioEffectSpectrumAnalyzer on dedicated bus)
 ├── Camera2D           — Pan / zoom with hard grid-edge limits
 ├── GameUI             — Entire HUD built programmatically (CanvasLayer)
 └── QuadGridMode (on demand) — 4 independent grid panels with own AudioEngine each
      └── QuadGridUI    — Overlay for quad mode
```

An IntroMenu is shown on `_ready()`; `_start_game(config)` wires the initial grid/tempo/preset/pattern. A `ChipsDebugPanel` overlay is created on-demand when the user toggles Chips From Audio mode.

### Game Loop
Each tick (default 0.2s, ~5/sec):
1. `LifeGrid.tick_simulation()` — heat dissipation, next generation, snapshot
2. `ClusterManager.detect_clusters()` — BFS flood-fill, persistent IDs across ticks
3. `FitnessManager.on_tick()` — decay, stable bonus, library similarity (every 10 ticks)
4. `CatalystEvents.on_tick()` — token generation (1 per 50 ticks, max 3) + fires scheduled tick-based effects
5. `GameUI.update_tick()` — refreshes HUD, sparklines, cluster cards
6. `AudioEngine.play_clusters()` — extends per-cluster note schedule up to a 0.8s look-ahead horizon (independent of grid tick rate)
7. `_chips_tick_spawn()` — if Chips overlay is active, spawns cells in tonal regions matching currently-active pitch classes in the audio FFT

### DNA System
Each cell holds a `genome: Array[DNANote]`. `DNANote` has `pitch` (0–11), `duration` (1–8 sixteenth-note units), `velocity` (0–127), `articulation` (0=legato…3=accent).

**Birth** = crossover of 3 neighbors (2 dominant parents, 50/50 note inheritance) + mutation.
**Mutation rate** = 5% base, ×2.5 in hot zones, ×0.2 in cold zones, inversely scaled by fitness.

### Clusters
Connected live cells form a `Cluster`. Each cluster has:
- `fitness_score` (0–100, starts 50); player like +15, mute −20, decay −0.1/tick
- Melody synthesized from cell genomes; cluster size → volume, density → timbre, age → articulation
- State snapshots every 5 ticks (ring buffer of 10) for the **Rewind** tool

### Tonal Regions
Configurable harmonic zone system with **2 map modes** and **6 presets**:

**Map modes:**
- `MAP_STANDARD` — Configurable grid of scale zones
- `MAP_ISLAND` — 12 note islands (piano-keyboard layout) with paintable zones

**Presets (Standard mode):**
| Preset | Grid | Description |
|--------|------|-------------|
| Classic | 3×2 | Original 6 regions (C Maj, G Maj, D Maj, A Min, E Min, E Phrygian) |
| 12Maj | 4×3 | All 12 chromatic roots, Major scale |
| 12Min | 4×3 | All 12 roots, Natural Minor |
| 5ths | 4×3 | Circle of 5ths, all Major |
| 7Modes | 4×2 | 7 modes of C Major + Chromatic |
| Dorian | 4×3 | All 12 roots, Dorian mode |

**Available scale types (11):** Major, Natural Minor, Dorian, Phrygian, Lydian, Mixolydian, Locrian, Harmonic Minor, Pentatonic Major, Pentatonic Minor, Blues.

Cells born in a region are constrained to that scale. 3-cell-wide boundary zones have elevated mutation.

### Audio Engine
**Sample-based playback.** `AudioEngine` loads .ogg samples from `res://samples/` via `SampleBank` (8 instrument folders, MIDI 21–108). A pool of 24 `AudioStreamPlayer` nodes handles polyphony with voice stealing (oldest note wins). A per-cluster scheduler fills an event queue up to a 0.8s look-ahead horizon, and `_process()` fires notes when their absolute `fire_time` is reached. This decouples melody playback from simulation tick rate.

Volume uses quadratic distance falloff from the listening centre (mouse on grid). Muted clusters are excluded from the schedule. Articulation modifies velocity and duration (staccato shortens, tenuto lengthens, accent boosts velocity). `active_midi_notes` is consumed by `GameUI` to animate the piano visualiser.

**8 instrument presets** (index → folder):
Guitar (`guitar-nylon`), Piano (`piano`), Organ (`organ`), Strings (`cello`), Acoustic (`guitar-acoustic`), Wind (`saxophone`), Bass (`bass-electric`), Pad (`violin`). Default tempo 120 BPM.

### Default Grid
**30×20 cells, 28 px per cell** (set in `main.gd::_start_game()`). The Settings panel exposes larger presets (up to 160×120). Max simultaneous voices: 24.

### Keyboard Shortcuts
| Key | Action |
|-----|--------|
| Space | Toggle pause |
| R | Seed random cells |
| C | Clear grid |
| 1–9 | Simulation speed (1 / 2 / 3 / 5 / 8 / 10 / 13 / 16 / 20 tps) |
| +, − | Fine-tune tick interval |
| F, Home | Reset camera to fit |
| F11 | Toggle fullscreen |
| Middle-mouse drag | Pan camera |
| Mouse wheel | Zoom camera |

In quad mode, keys 1–4 switch active panel, and Space / R / C apply only to that panel.

### Player Tools (selected via UI — left panel 🔧 Tools tab)
| Tool | Effect |
|------|--------|
| SELECT | Info on clusters |
| HOT ZONE | ↑mutation, ↑birth/survival |
| COLD ZONE | ↓mutation, strict rules |
| ATTRACT | Green beacon pulls clusters |
| REPEL | Orange beacon pushes clusters |
| DNA INJECT | Inject default 4-note motif at click (15-tick cooldown) |
| REWIND | Revert cluster to a saved state (3 uses/session) |
| SPLIT | Click start + end to cut a cluster along a line |
| DRAW | Manually paint live cells |
| ERASE | Delete cells |
| PAINT REGION | Paint custom tonal zones (active in Island map mode) |

### Catalyst Events (token cost: 1)
☄️ Meteorite, 🤝 Resonance, ❄️ Freeze, 🌊 Mutation Wave, 🎭 Mirror.

**Freeze** (20 ticks) and **Mutation Wave** (10 ticks) use tick-based `_scheduled_effects` — their duration is invariant to simulation speed changes.

### UI Layout (GameUI)
The HUD is built entirely in GDScript. **Single-row top bar (44px):** title, tick counter, speed slider, pause button, Random/Clear, settings ⚙, fullscreen ⛶, quad-mode ⊞, **chips 🎮** (toggle Chips From Audio overlay), token display.

**Left panel (260px) — TabContainer:**
- Tab 🔧 Tools: 11 tools, draw-pitch keyboard (12 notes), listen zone slider, paint zone selector, 5 catalyst event buttons
- Tab 🌍 World: map mode (Standard/Islands), 6 presets, cell color mode, seed buttons
- Tab 🎵 Sound: 8 instruments, 8 genre presets, volume / mutation sliders (the legacy "Timbre" slider currently has no audible effect under sample-based playback)

**Right panel (260px) — Cluster Evolution Panel:**
- Sparklines: cell count + avg fitness (slice from EvolutionTracker's 200-tick ring buffer)
- Latest milestone label
- Collapsible rules/fitness info, Library button
- Live cluster cards (top 6 by size): colored header, fitness bar, note blocks (HSV by pitch, width by duration, yellow border on active note), action buttons (● ♥ 🔇 💾 ❄ 🎭). Cards are cached and reused across ticks (keyed by cluster_id) to avoid GC churn.

**Bottom:** StatusBar (vp.x − 520px wide) + Piano visualiser (74px tall, MIDI 36–84). LibraryPanel, SettingsPanel, and the Chips overlay are floating CanvasLayer overlays.

### Fitness Scoring Details
| Action | Fitness Change |
|--------|---------------|
| Player "like" | +15 (one-shot) |
| Player "mute" | −20 (one-shot) + silences the cluster in AudioEngine |
| Natural decay per tick | −0.1 |
| Stable cluster bonus | +0.5 per tick |
| Library similarity >70% | +10, applied only on ticks where `tick % 10 == 0` |
| Library similarity 50–70% | +5, applied only on ticks where `tick % 10 == 0` |

Library bonus is cached per cluster in `_last_lib_bonus` and evicted when clusters die. Stable bonus was reduced from +5.0 → +0.5 to fix runaway fitness capping (fixed 2026-04).

### Chips From Audio (overlay on the main game)
External audio file (.ogg/.mp3) → FFT analysis → spawn cells in tonal regions whose root matches each active pitch class.

**Activation:** 🎮 button in the top bar. The main simulation keeps running underneath.

**Components:**
- `ChipsAudioAnalyzer` — wraps `AudioEffectSpectrumAnalyzer` on a dedicated "ChipsAnalysis" bus. Returns smoothed per-pitch-class energy across a configurable octave range (default C2–C8). Uses lerp smoothing and a dB threshold floor.
- `ChipsDebugPanel` (380 px, right-edge CanvasLayer overlay) — file loader, track/notes volume sliders, analyzer settings (threshold dB, smoothing), spawn settings (min energy, cells/note), 12 manual-spawn buttons laid out in Circle-of-Fifths order with consonance colouring, auto-consonant strength, 12 per-interval affinity sliders + presets (Theory, Pentatonic, All+, All−, Random).
- `ChipsFreqViz` — simple 12-bar visualiser, HSV-coloured by pitch class.
- `ChipsLifeGrid extends LifeGrid` — used by the standalone Chips mode: 12 columns in Circle-of-Fifths order × 5 octave rows; overrides `_next_generation()` to add an affinity layer (consonant neighbours → birth bonus, dissonant → extra deaths).
- `ChipsFromAudioMode` — self-contained orchestrator for the standalone Chips grid. **Not currently invoked from `main.gd`** — the live flow uses the overlay variant that spawns into the main grid via `_chips_tick_spawn()` / `_chips_spawn_in_region()`.

**Main-grid overlay flow:** per tick, iterate FFT energy; for each pitch class whose energy > threshold, spawn N cells inside grid positions whose tonal region has that pitch as its root (precomputed into `_chips_pitch_cells`). The auto-consonant slider additionally spawns harmonically related notes using a 12×12 affinity matrix built from interval-theory consonance values.

### Quad Grid Mode
Toggle via ⊞ in the top bar. Creates 4 independent `LifeGrid` + `ClusterManager` + `AudioEngine` panels inside `QuadGridMode`. Keys 1–4 switch the active panel; Space / R / C act only on the active one. Entering and exiting the mode calls `_start_game()`, which resets the main grid.

**Caveat:** all four grids share the static `LifeGrid.GRID_W / GRID_H / CELL_SIZE` — resizing one affects all.

## Key Files

| File | Responsibility |
|------|----------------|
| `main.gd` | Orchestration, signal wiring, game loop callbacks, Chips overlay, Camera2D, quad-mode toggle |
| `scripts/life_grid.gd` | Simulation engine: Life rules, DNA crossover, heat zones, snapshots, rendering |
| `scripts/cluster_manager.gd` | BFS cluster detection, ID persistence across ticks |
| `scripts/cluster.gd` | Organism data: cells, fitness, melody, playback state |
| `scripts/audio_engine.gd` | Sample-based playback, 24-voice pool, look-ahead scheduler, listening-zone volume |
| `scripts/sample_bank.gd` | .ogg loader; binary-search nearest MIDI + `pitch_scale` transposition |
| `scripts/game_ui.gd` | Entire HUD (44px top bar, left tabs, right evolution panel, piano visualiser) |
| `scripts/intro_menu.gd` | Start screen: Quick Start, Sandbox config, Settings (audio/video/hotkeys) |
| `scripts/evolution_tracker.gd` | Ring buffer (200 ticks) for cell counts, avg fitness, named milestones |
| `scripts/fitness_manager.gd` | Feedback scoring, melody library, similarity (Levenshtein), cooldowns |
| `scripts/tool_manager.gd` | Tool state, grid event routing (11 tools) |
| `scripts/catalyst_events.gd` | Token economy, 5 events, tick-based `_scheduled_effects` |
| `scripts/tonal_regions.gd` | Scale zones, 6 presets, 2 map modes, boundary mutation, pitch constraining |
| `scripts/cell_state.gd` | Cell data class (alive, genome, age, tonal_region, frozen) |
| `scripts/dna_note.gd` | Note data class (pitch, duration, velocity, articulation) |
| `scripts/chips_audio_analyzer.gd` | FFT wrapper on dedicated audio bus; per-note energy |
| `scripts/chips_debug_panel.gd` | 380 px right-edge overlay for Chips mode (file, volumes, spawn, affinity) |
| `scripts/chips_freq_viz.gd` | 12-bar frequency visualiser |
| `scripts/chips_life_grid.gd` | `LifeGrid` subclass for the standalone Chips mode — affinity-layer generation |
| `scripts/chips_from_audio_mode.gd` | Standalone Chips-mode orchestrator (currently unused by main.gd) |
| `scripts/quad_grid_mode.gd` | 4-panel mode, per-panel simulation / audio |
| `scripts/quad_grid_ui.gd` | Overlay UI for quad mode |
| `samples/` | 8 instrument folders of .ogg sample banks |
| `life-melody-mechanics.md` | Detailed design document (Ukrainian) |
| `PROJECT_AUDIT_LIFODY.md` | Per-module audit, bug catalogue, readiness scores (2026-04-16) |
| `UI_CHANGELIST.md` | QA checklist template for verifying fix bundles |

## Tech Stack

- **Engine:** Godot 4.6, GDScript only (no C#)
- **Rendering:** OpenGL Compatibility (D3D12 on Windows)
- **Physics:** Jolt Physics
- **Audio:** sample-based playback — 8 instruments × up to 88 MIDI notes in `samples/**.ogg`; `AudioEffectSpectrumAnalyzer` on a dedicated bus for Chips From Audio mode
- **Data:** Arrays/Dictionaries; JSON only for rewind snapshots
- **No external code dependencies** beyond Godot 4.6 built-ins (the `samples/` .ogg bank is the only external asset dependency)

---

## Change History

- **2026-04-17:** Sample-based AudioEngine + `SampleBank`; Chips From Audio mode (FFT → cell spawning, overlay on main grid); `QuadGridMode`; tick-based Catalyst effects (`_scheduled_effects`); fitness balance fixes (stable bonus +5 → +0.5, library bonus cadence every 10 ticks); mute actually silences AudioEngine; Camera2D pan/zoom with grid-edge limits; default grid 30×20 @ 28 px; cluster cards reused across ticks.
- **2026-03-26:** UI redesign — dual 260px panel layout, IntroMenu, EvolutionTracker; updated CLAUDE.md to match
- **2026-03-23:** Updated CLAUDE.md: tonal presets, map modes, scale types, DRAW/PAINT_REGION tools, 2-row top bar, audio presets, fitness scoring table
