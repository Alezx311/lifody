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
 ├── LifeGrid        — Game of Life simulation + DNA crossover/mutation
 ├── ClusterManager  — BFS clustering to find connected groups (organisms)
 ├── AudioEngine     — Real-time additive synthesis, ADSR envelopes, 8 instrument presets
 ├── FitnessManager  — Player feedback scoring, melody library, similarity matching
 ├── ToolManager     — Routes player tool interactions to the grid (11 tools)
 ├── CatalystEvents  — 5 special one-shot events, token economy
 ├── TonalRegions    — Configurable harmonic zones (6 presets, 2 map modes, 11 scale types)
 └── GameUI          — Entire HUD built programmatically in GDScript (2-row top bar)
```

### Game Loop
Each tick (default 0.2s, ~5/sec):
1. `LifeGrid` advances simulation (modified Life rules + DNA crossover)
2. `ClusterManager` detects connected groups via BFS
3. `FitnessManager` applies decay/bonuses per tick
4. `CatalystEvents` checks token generation (1 token per 50 ticks, max 3)
5. `GameUI` refreshes all displays

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
Pure GDScript additive synthesis. 44,100 Hz, 80 ms buffer, max 12 simultaneous voices. Tempo syncs to grid ticks (default 120 BPM).

**8 instrument presets:** Synth, Piano, Organ, Strings, Bell, Flute, Bass, Pad.

### Default Grid
80×60 cells, 12 pixels per cell.

### Player Tools (keys 1–0)
| Key | Tool | Effect |
|-----|------|--------|
| 1 | SELECT | Info on clusters |
| 2 | HOT ZONE | ↑mutation, ↑birth/survival |
| 3 | COLD ZONE | ↓mutation, strict rules |
| 4 | ATTRACT | Green beacon pulls clusters |
| 5 | REPEL | Orange beacon pushes clusters |
| 6 | DNA INJECT | Piano-roll to inject custom melody |
| 7 | REWIND | Revert cluster to saved state (3 uses/session) |
| 8 | SPLIT | Draw line to split cluster |
| 9 | DRAW | Manually paint live cells |
| 0 | ERASE | Delete cells |

**Additional tool:** PAINT_REGION — paint custom tonal zones (active in Island map mode, available via UI).

### Catalyst Events (token cost: 1)
☄️ Meteor, 🤝 Resonance, ❄️ Freeze, 🌊 Mutation Wave, 🎭 Mirror

### UI Layout (GameUI)
The HUD is built entirely in GDScript. Top bar is **64px tall, split into 2 rows**:
- **Row 1:** Title, tick counter, speed slider, pause, seed buttons (Random/Glider/R-Pentomino), clear, camera hint
- **Row 2:** Map mode (Standard/Islands), map presets (12Maj, 12Min, 5ths, 7Modes, Dorian, Classic), cell color mode (Age/Note), settings ⚙, sound toggle 🎵, fullscreen ⛶, token display

Side panels: ToolPanel (left, 120px), InfoPanel (right, 200px), StatusBar (bottom), LibraryPanel (overlay), SettingsPanel (overlay).

### Fitness Scoring Details
| Action | Fitness Change |
|--------|---------------|
| Player "like" | +15 |
| Player "mute" | −20 |
| Natural decay per tick | −0.1 |
| Stable cluster bonus | +5 |
| Library similarity >70% | +10 |
| Library similarity 50–70% | +5 |

## Key Files

| File | Responsibility |
|------|----------------|
| `main.gd` | Orchestration, signal wiring, game loop callbacks |
| `scripts/life_grid.gd` | Simulation engine: Life rules, DNA crossover, heat zones, snapshots |
| `scripts/cluster_manager.gd` | BFS cluster detection, ID persistence across ticks |
| `scripts/cluster.gd` | Organism data: cells, fitness, melody, playback state |
| `scripts/audio_engine.gd` | Synthesis scheduler, ADSR, polyphony management, 8 presets |
| `scripts/game_ui.gd` | Entire HUD (2-row top bar, panels, buttons, cluster list, fitness bars) |
| `scripts/fitness_manager.gd` | Feedback scoring, melody library, similarity (Levenshtein), cooldowns |
| `scripts/tool_manager.gd` | Tool state, grid event routing (11 tools) |
| `scripts/catalyst_events.gd` | Token economy, 5 special event implementations |
| `scripts/tonal_regions.gd` | Scale zones, 6 presets, 2 map modes, boundary mutation, pitch constraining |
| `scripts/cell_state.gd` | Cell data class (alive, genome, age) |
| `scripts/dna_note.gd` | Note data class (pitch, duration, velocity, articulation) |
| `life-melody-mechanics.md` | Detailed design document (Ukrainian) |

## Tech Stack

- **Engine:** Godot 4.6, GDScript only (no C#)
- **Rendering:** OpenGL Compatibility mode (D3D12 on Windows)
- **Physics:** Jolt Physics
- **Audio:** Pure GDScript synthesis (no external audio assets), 8 instrument presets
- **Data:** Arrays/Dictionaries; JSON for rewind snapshots only
- **No external dependencies** beyond Godot 4.6 built-ins

---

## Change History

- **2026-03-23:** Updated CLAUDE.md to match actual codebase:
  - Added tonal region presets (6 presets), map modes (Standard/Island), 11 scale types
  - Added missing tools: DRAW (key 9) and PAINT_REGION
  - Documented 2-row top bar layout (64px)
  - Added audio engine instrument presets (8 types)
  - Added default grid size (80×60, 12px cells)
  - Added detailed fitness scoring table with library similarity tiers
  - Updated system wiring diagram to reflect actual capabilities
