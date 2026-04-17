# PROJECT AUDIT — Lifody

**Дата аудиту:** 2026-04-16
**Всього рядків GDScript:** 6,824 (21 файл)
**Engine:** Godot 4.6, GDScript only, OpenGL Compatibility / D3D12
**Залежності:** жодних зовнішніх — тільки Godot built-ins + власні .ogg семпли

---

## 1. Архітектура

### 1.1 Граф систем (main.gd — 635 рядків)

```
main.gd (Node2D)
├── TonalRegions        — 320 рядків, гармонічні зони
├── LifeGrid            — 690 рядків, симуляція + рендеринг
├── ClusterManager      — 198 рядків, BFS кластеризація
├── AudioEngine         — 322 рядки, sample-based polyphony
│   └── SampleBank      — 119 рядків, завантаження .ogg семплів
├── FitnessManager      — 170 рядків, fitness scoring + library
├── ToolManager         — 285 рядків, 11 інструментів гравця
├── CatalystEvents      — 242 рядки, 5 подій з токен-економікою
├── EvolutionTracker    — 96 рядків, ring buffer метрик
├── ChipsAudioAnalyzer  — ~150 рядків, FFT для зовнішнього аудіо
├── GameUI              — 1,357 рядків, повний HUD (CanvasLayer)
├── IntroMenu           — 566 рядків, стартове меню
├── Camera2D            — вбудований, zoom/pan
└── QuadGridMode        — ~200 рядків, 4-панельний режим
    └── QuadGridUI      — ~120 рядків, overlay для quad mode
```

### 1.2 Data-only класи
- `CellState` — 62 рядки, стан клітини (alive, genome, age, tonal_region, frozen)
- `DNANote` — 70 рядків, нота геному (pitch, duration, velocity, articulation)
- `Cluster` — 115 рядків, кластер клітин (cells, fitness, melody, state)

### 1.3 Game Loop (кожен тік, default 0.2s)
1. `LifeGrid.tick_simulation()` — dissipate heat, next_generation(), snapshot
2. `ClusterManager.detect_clusters()` — BFS flood-fill, ID assignment
3. `FitnessManager.on_tick()` — decay, stable bonus, library similarity
4. `CatalystEvents.on_tick()` — token generation (1 per 50 ticks, max 3)
5. `GameUI.update_tick()` — оновлення дисплею, sparklines
6. `AudioEngine.play_clusters()` — look-ahead scheduling нот (0.8s горизонт)

---

## 2. Поточний стан по модулях

### 2.1 LifeGrid (life_grid.gd) — ПОВНИЙ

**Реалізовано:**
- Модифіковані правила Life з конфігурованими B/S правилами
- DNA crossover 3 сусідів (2 домінантних батьки, 50/50 спадкування)
- Мутація: 5% база, ×2.5 hot zone, ×0.2 cold zone, ×1.5 transition
- Heat zones з дисипацією (0.966× за тік, ~30 тіків)
- Beacons (attract/repel/resonance) з модифікацією виживання
- Frozen cells — ігнорують правила Life
- Snapshot ring buffer (10 знімків, кожні 5 тіків) для Rewind
- Drawing/erasing з хроматичним або scale-based pitch
- Listening zone (радіус навколо курсору)
- Повний рендеринг: tonal regions, heat map, beacons, cells (glow + body), vignette, listening ring, island map, custom regions

**Потенційні проблеми:**
- `_draw()` викликається кожен кадр (queue_redraw() у `_process`), що означає повний перерендер 80×60 = 4,800 клітин + glow кожен кадр. На великих гридах (160×120 = 19,200 клітин) це 2 проходи по всіх клітинах — ~38,400 draw_rect за кадр.
- `_alive_neighbors()` створює новий Array на кожну клітину кожен тік. На 80×60 = 4,800 клітин це 4,800 алокацій масивів за тік.
- `_next_generation()` створює повний новий 2D масив щотіка — 4,800 CellState.new() + можливі copy/crossover.
- `add_heat()` ітерує по всьому гриду (O(W×H)) для одного кліку.
- Статичні змінні `GRID_W`, `GRID_H`, `CELL_SIZE` на класі — в QuadGridMode всі 4 гриди ділять ці значення, що працює тільки поки всі мають однаковий розмір.

### 2.2 ClusterManager (cluster_manager.gd) — ПОВНИЙ

**Реалізовано:**
- BFS flood-fill (8-connected — функція називається `_nb4`, але повертає 8 сусідів)
- Persistent cluster IDs через spatial overlap з попереднім тіком
- Fitness persistence через `_fitness_store` dictionary
- Melody building (top→bottom, left→right, cap 16 нот)
- State classification (empty/still/stable/evolving/complex)

**Баги:**
- **BUG-01: Невірна назва функції `_nb4`** — повертає 8 сусідів (всі ортогональні + діагональні), але названа як 4-connectivity. Це лише naming issue, логіка коректна.
- **BUG-02: O(n²) overlap detection** — для кожного нового кластера ітерує всі клітини всіх попередніх кластерів. При 50 кластерах по 50 клітин = 125,000 перевірок.
- `_birth_ticks` dictionary ніколи не чиститься для мертвих кластерів, хоча `_fitness_store` чиститься коректно. Memory leak (мінімальний, int → int).

### 2.3 AudioEngine (audio_engine.gd) — ПОВНИЙ, рефакторинг

**Реалізовано:**
- Sample-based playback з SampleBank (8 інструментів, .ogg файли)
- Look-ahead scheduling: 0.8s горизонт, scheduler per cluster
- 24-voice polyphony pool з voice stealing (oldest note)
- Distance-based volume (quadratic falloff від listening zone)
- Articulation mapping: staccato (×0.75 vol, ×0.45 dur), tenuto (×1.4 dur), accent (×1.35 vol)
- `active_midi_notes` dictionary для piano visualization

**Проблеми:**
- **BUG-03: `harmonic_mix` property — dead code.** Документація в коментарях каже "With sample-based playback this has no effect", але UI все ще показує "Timbre" слайдер, що змінює `harmonic_mix`. Це misleading — слайдер не робить нічого.
- Listening center завжди слідує за мишею (`_grid.to_local(_grid.get_global_mouse_position())`), навіть якщо listening_radius == 0 (hear everything). Непотрібна обробка.

### 2.4 SampleBank (sample_bank.gd) — ПОВНИЙ

**Реалізовано:**
- Завантажує .ogg файли для MIDI 21-108 (A0-C8) з `res://samples/`
- Binary search найближчого семплу + pitch_scale transposition
- 8 інструментальних папок

**Проблеми:**
- **BUG-04: Коментарі INSTRUMENT_NAMES не збігаються з FOLDERS.** AudioEngine називає пресети "Guitar, Piano, Organ, Strings, Acoustic, Wind, Bass, Pad", але SampleBank маппить їх на "guitar-nylon, piano, organ, cello, guitar-acoustic, saxophone, bass-electric, violin". Тобто "Strings" = cello, "Acoustic" = guitar-acoustic (але іконка 🎸 = Bell), "Wind" = saxophone (але іконка 🎷), "Pad" = violin. GameUI ще більше заплутує: іконки `["🎸","🎹","🎸","🎻","🎸","🎷","🎸","🎻"]` не відповідають реальним інструментам. Наприклад, "Organ" має іконку 🎸 замість орган-emoji.

### 2.5 FitnessManager (fitness_manager.gd) — ПОВНИЙ

**Реалізовано:**
- Tick decay: -0.1/тік на кожен кластер
- Stable bonus: +5.0 для "stable" кластерів (кожен тік!)
- Library bonus: +10 (>70% similarity) або +5 (>50%)
- Like (+15), Mute (-20 + toggle звуку)
- Melody library: save/delete, Levenshtein similarity
- Rewind budget (3 per session)
- DNA injection cooldown (15 тіків)

**Баги:**
- **BUG-05: Stable bonus +5.0 на КОЖЕН тік — надто щедро.** При 5 tps це +25 fitness/секунду. Кластер зі стейтом "stable" (2-4 клітини) буде мати max fitness (100) за ~10 секунд, а decay -0.1/тік не встигає компенсувати. Вірогідно мало бути +0.5 або +1.0.
- **BUG-06: Library bonus рахується на КОЖЕН тік.** Якщо кластер має >70% similarity з бібліотекою, він отримує +10 КОЖЕН тік. При 5 tps це +50/сек. Це робить library bonus домінантним і неможливим для балансу.
- `on_tick()` викликає `cluster_mgr.update_fitness(cid, 0.0)` — це записує поточний fitness в store, але delta=0.0. Працює як sync, але семантично незрозуміло.
- `_melody_similarity()` доступна ззовні через `_` prefix (private convention) — `CatalystEvents.event_resonance()` викликає `fitness_mgr._melody_similarity()` напряму.

### 2.6 ToolManager (tool_manager.gd) — ПОВНИЙ

**Реалізовано:**
- 11 інструментів: Select, Draw, Erase, Paint Region, Hot/Cold Zone, Attract/Repel Beacon, DNA Inject, Rewind, Split
- Drag support для Heat, Draw, Erase, Paint Region, Split
- Beacon limit (max 5, FIFO removal)
- Split: line-based з distance-to-line обчисленням
- Default inject genome: 4-note ascending motif

**Проблеми:**
- Split tool потребує 2 окремих кліки (start + end), але UX може бути незрозумілим — tooltip каже "drag to draw cut line" але реально це 2 кліки, не drag.
- `_build_default_inject_genome` створює тривіальний мотив [0,1,2,3] — мало музичного сенсу.

### 2.7 CatalystEvents (catalyst_events.gd) — ПОВНИЙ

**Реалізовано:**
- 5 подій: Meteorite, Resonance, Freeze, Mutation Wave, Mirror
- Token economy: 1 per 50 ticks, max 3, start with 1
- Proper refund on failure (no cluster to freeze, less than 2 clusters for resonance)

**Баги:**
- **BUG-07: Freeze timer based on wall-clock, not ticks.** `create_timer(20.0 * grid.tick_interval)` використовує поточний `tick_interval` — якщо гравець змінить швидкість під час заморозки, розморозка станеться невчасно. При прискоренні з 5 tps до 20 tps, таймер fire після лише 5 "game ticks" замість запланованих 20.
- **BUG-08: Mutation Wave timer — та сама проблема.** `create_timer(10.0 * grid.tick_interval)` — при зміні швидкості ефект може тривати занадто довго або занадто коротко.
- `event_mirror()` обчислює `mirror_offset` як `Vector2i(GRID_W - 1 - center.x * 2, GRID_H - 1 - center.y * 2)`. Це дзеркалить відносно центру грида, але offset додається до кожної позиції клітини (не до центру). Це означає, що кластер біля краю буде дзеркалитись далеко за межі грида і clamp'ується до країв — результат може бути стиснутим в лінію.

### 2.8 TonalRegions (tonal_regions.gd) — ПОВНИЙ

**Реалізовано:**
- 133 регіони: 12 нот × 11 гам + 1 Chromatic
- 2 map modes: Standard (grid) та Island (12 островів + paintable)
- 6 пресетів: Classic, 12Maj, 12Min, Circle of 5ths, 7 Modes, Dorian
- Transition zones (3 cell width) з підвищеною мутацією
- Custom region painting (circular brush)

**Проблеми:**
- Legacy boundary helpers (`boundary_px_x`, `boundary_px_y`, `drag_boundary_x`, `drag_boundary_y`) — dead code, повертають 0.0/pass. Можна видалити.
- Island positions hardcoded для 80×60 grid. При resize_grid вони стають невідповідними.

### 2.9 GameUI (game_ui.gd) — ПОВНИЙ, найбільший файл

**Реалізовано:**
- Top bar (44px): title, tick, speed slider, pause, random, clear, settings, fullscreen, quad, chips, tokens
- Left panel (260px): TabContainer з 3 табами (Tools, World, Sound)
- Right panel (260px): Evolution sparklines, rules/fitness info, live cluster cards (top 6)
- Bottom: Status bar + Piano visualiser (74px, MIDI 36-84)
- Settings overlay: Grid size presets, Life rules (B/S notation), rule presets
- Library panel: save/play/delete melodies
- Genre presets: 8 конфігурацій (Classical, Ambient, Rock, Jazz, Bells, Orchestra, Chaos, Folk)
- Responsive resize, keyboard animation, tween button animations

**Проблеми:**
- **BUG-09: Cluster cards recreated every tick.** `update_cluster_display()` → `_refresh_cluster_cards()` calls `queue_free()` on ALL children and recreates them. При 5 tps і 6 кластерах це ~60 нових Control nodes/sec + GC на старих. Це головне джерело потенційного GC pressure.
- **BUG-10: Region selector hardcoded.** `_build_region_selector()` hardcodes 8 кнопок з конкретними region_ids (0, 77, 22, 100, 45, 47, 132, -1) що відповідають Classic preset. При зміні preset ці кнопки стають невідповідними.
- Piano visualiser keys порахований для фіксованого MIDI діапазону, але при зміні розміру вікна пропорції чорних клавіш можуть бути невідповідні (minor cosmetic issue).

### 2.10 IntroMenu (intro_menu.gd) — ПОВНИЙ

**Реалізовано:**
- Stack-based навігація (main / sandbox / settings_audio / settings_video / settings_hotkeys)
- Повноекранний режим, volume, instrument, color mode
- Genre presets, pattern, scale, mutation rate, tempo
- Hotkeys reference table
- Proper panel auto-resize

**Чисто, без значних проблем.**

### 2.11 EvolutionTracker (evolution_tracker.gd) — ПОВНИЙ

**Реалізовано:**
- Ring buffer 200 тіків для cell count і avg fitness
- Named milestones (max 20, FIFO)
- "Перший кластер" milestone автоматично

**Чисто, без проблем.**

### 2.12 QuadGridMode + QuadGridUI — ЧАСТКОВИЙ (~70%)

**Реалізовано:**
- 4 незалежних Life Grid панелі з власними TonalRegions, ClusterManager, AudioEngine
- Active panel switching (keys 1-4)
- Per-panel pause, seed, clear

**Проблеми:**
- Всі 4 гриди ділять статичні `LifeGrid.GRID_W/H/CELL_SIZE` — resize одного впливає на всі.
- UI обмежений — немає per-panel controls для інструментів чи жанрів.
- Вхід/вихід з quad mode викликає `_start_game()` — втрачає стан основного грида.

### 2.13 Chips Audio Mode — ЧАСТКОВИЙ (~75%)

**Реалізовано:**
- FFT аналіз зовнішнього аудіо файлу (.ogg/.mp3)
- Per-note energy detection (12 нот × N октав)
- Auto-spawn клітин в тональних регіонах за pitch
- Consonance display (12×12 music-theory affinity matrix)
- Debug panel з controls (threshold, spawn rate, auto-consonant strength)

**Проблеми:**
- `_chips_tick_spawn()` спавнить клітини по всіх 12 нотах кожен тік, якщо energy > threshold. Немає rate limiting — при голосному аудіо це flood клітинами.

---

## 3. Знайдені баги — зведена таблиця

| ID | Серйозність | Файл | Опис |
|----|-------------|------|------|
| BUG-01 | Low | cluster_manager.gd:85 | `_nb4()` повертає 8 сусідів, не 4. Naming issue. |
| BUG-02 | Medium | cluster_manager.gd:100-155 | O(n²) overlap detection для ID persistence. |
| BUG-03 | Low | audio_engine.gd:53, game_ui.gd:619-629 | `harmonic_mix` dead property, "Timbre" слайдер нічого не робить. |
| BUG-04 | Low | sample_bank.gd:9-18, game_ui.gd:531 | Невідповідність назв інструментів та іконок в UI. |
| BUG-05 | **High** | fitness_manager.gd:44-45 | Stable bonus +5.0/тік — надто щедрий, fitness cap за ~10с. |
| BUG-06 | **High** | fitness_manager.gd:47-48 | Library bonus +10/+5 на КОЖЕН тік, робить library OP. |
| BUG-07 | Medium | catalyst_events.gd:174 | Freeze timer wall-clock, не тіковий. Зміна швидкості ламає. |
| BUG-08 | Medium | catalyst_events.gd:195 | Mutation Wave timer — та сама проблема. |
| BUG-09 | Medium | game_ui.gd:718-741 | Cluster cards пересторюються кожен тік — GC pressure. |
| BUG-10 | Low | game_ui.gd:409-442 | Region selector hardcoded під Classic preset. |

---

## 4. Можливості для покращення

### 4.1 Продуктивність (Performance)

**P-01: Подвійний прохід рендеринга клітин**
`_draw_cells()` робить 2 проходи по всьому гриду (glow + body). На великих гридах (160×120) це ~38,400 `draw_rect()` за кадр.
- **Рекомендація:** Використовувати `RenderingServer` для batch rendering або рендерити в texture і оновлювати тільки змінені клітини.

**P-02: Алокація масивів в _alive_neighbors**
Кожен виклик створює новий Array. На 80×60 = 4,800 клітин × тік = 24,000 масивів/сек при 5 tps.
- **Рекомендація:** Передавати pre-allocated buffer або рахувати сусідів inline без масиву.

**P-03: _next_generation створює повний новий 2D масив**
4,800 CellState.new() + можливі .copy() щотіка.
- **Рекомендація:** Double-buffering (два масиви, swap між тіками).

**P-04: add_heat ітерує весь грид**
O(W×H) на кожен клік/drag. При drag по гриду це ~50-100 повних ітерацій.
- **Рекомендація:** Ітерувати тільки bounding box `[gx-radius, gx+radius] × [gy-radius, gy+radius]`.

### 4.2 Геймплей (Gameplay)

**G-01: Балансування fitness системи**
BUG-05 і BUG-06 роблять fitness практично марним — все швидко досягає 100. Після фіксу потрібен повний rebalance.
- **Рекомендація:** Stable bonus → +0.5/тік, Library bonus → перевіряти раз на 10 тіків, не кожен.

**G-02: Mute не впливає на аудіо**
`FitnessManager.mute_cluster()` тільки змінює fitness і записує стан в `muted_clusters`, але `AudioEngine.play_clusters()` не перевіряє `muted_clusters`. Muted кластери все одно граються.
- **Рекомендація:** Передавати `muted_clusters` в AudioEngine або фільтрувати кластери перед `play_clusters()`.

**G-03: DNA Inject UX**
Piano-roll для створення кастомної мелодії існує тільки як draw pitch selector. Немає UI для побудови inject_genome з кількох нот — використовується default 4-note ascending motif.
- **Рекомендація:** Додати мініатюрний piano-roll для композиції inject мелодії.

**G-04: Відсутні visual effects для catalyst events**
Meteorite, Resonance, Freeze тощо не мають візуального feedback окрім status message. Немає анімацій, партиклів, screen shake.
- **Рекомендація:** Додати прості tween анімації (flash, shake, particle burst).

### 4.3 Код (Code Quality)

**C-01: Dead code cleanup**
- `TonalRegions.boundary_px_x/y`, `drag_boundary_x/y` — legacy, не використовується
- `AudioEngine.harmonic_mix` — не має ефекту з sample-based playback
- `Cluster.advance_melody()`, `get_current_note()` — не викликаються ніде (AudioEngine використовує власний scheduler)

**C-02: Naming inconsistency**
- `_nb4` → має бути `_nb8` (повертає 8 сусідів)
- `SampleBank.FOLDERS` коментарі не збігаються з AudioEngine.INSTRUMENT_NAMES
- GameUI tool_defs порядок не збігається з ToolManager.Tool enum

**C-03: Static var sharing в QuadGridMode**
`LifeGrid.GRID_W/H/CELL_SIZE` як static vars означає, що всі інстанси LifeGrid ділять розмір. Це працює тільки при однаковому розмірі. Перетворити на instance vars.

**C-04: Timer-based events vs tick-counting**
CatalystEvents використовує wall-clock timers для tick-based ефектів. Замінити на tick counting (зберігати `end_tick` і перевіряти в `on_tick()`).

### 4.4 UX/UI

**U-01: Keyboard shortcuts конфліктують з tools**
Клавіші 1-9 контролюють швидкість, але CLAUDE.md каже "keys 1–0" для інструментів. Реально інструменти вибираються через UI кнопки, не клавіатурою. Це розбіжність з документацією.

**U-02: Genre presets не показують поточний вибір**
При натисканні genre preset (Classical, Rock, etc.) кнопка не виділяється — гравець не бачить який жанр активний.

**U-03: Settings не зберігаються між сесіями**
Немає persistence — все скидається при перезапуску.
- **Рекомендація:** Зберігати в `user://settings.json`.

---

## 5. Стан файлів

| Файл | Рядки | Стан | Якість |
|------|-------|------|--------|
| main.gd | 635 | Complete | Чистий, добре організований |
| scripts/life_grid.gd | 690 | Complete | Потребує performance optimization |
| scripts/game_ui.gd | 1,357 | Complete | Великий моноліт, але функціональний |
| scripts/intro_menu.gd | 566 | Complete | Чистий |
| scripts/audio_engine.gd | 322 | Complete | Добре спроектований (look-ahead) |
| scripts/tonal_regions.gd | 320 | Complete | Чистий, має dead code |
| scripts/tool_manager.gd | 285 | Complete | Добрий |
| scripts/catalyst_events.gd | 242 | Complete | Має timer bugs |
| scripts/cluster_manager.gd | 198 | Complete | Має performance issues |
| scripts/fitness_manager.gd | 170 | Complete | Має balance bugs |
| scripts/sample_bank.gd | 119 | Complete | Чистий |
| scripts/cluster.gd | 115 | Complete | Має dead methods |
| scripts/evolution_tracker.gd | 96 | Complete | Чистий |
| scripts/dna_note.gd | 70 | Complete | Чистий |
| scripts/cell_state.gd | 62 | Complete | Чистий |
| scripts/quad_grid_mode.gd | ~200 | 70% | Static var issues |
| scripts/quad_grid_ui.gd | ~120 | 70% | Basic |
| scripts/chips_audio_analyzer.gd | ~150 | 75% | Functional |
| scripts/chips_debug_panel.gd | ~100 | 75% | Basic UI |
| scripts/chips_freq_viz.gd | ~80 | 75% | Visualization |
| scripts/chips_life_grid.gd | ~50 | 60% | Adapter |

---

## 6. Оцінка готовності

| Аспект | Оцінка | Коментар |
|--------|--------|----------|
| Core simulation | 98% | Повний, тільки performance concerns |
| Audio system | 95% | Рефакторинг з additive → sample-based завершено, harmonic_mix dead code |
| UI/HUD | 92% | Повний, потребує cluster card optimization |
| Player tools | 95% | 11 інструментів працюють |
| Catalyst events | 85% | Timer bugs потребують фіксу |
| Fitness/Evolution | 75% | Balance bugs (BUG-05, BUG-06) потребують виправлення |
| Intro menu | 98% | Повний |
| Quad mode | 70% | Працює, але обмежений |
| Chips mode | 75% | Функціональний, потребує polish |
| Documentation | 95% | CLAUDE.md і README.md детальні |
| **Загальна готовність** | **~92%** | Production-ready з відомими balance issues |

---

## 7. Пріоритетний план дій

### Критичні фікси (1-2 години)
1. **FIX BUG-05:** `fitness_manager.gd:44-45` — змінити stable bonus з +5.0 на +0.5
2. **FIX BUG-06:** `fitness_manager.gd:47-48` — рахувати library bonus раз на 10 тіків
3. **FIX BUG-07/08:** `catalyst_events.gd` — замінити `create_timer()` на tick-counting

### Середній пріоритет (2-4 години)
4. **FIX BUG-09:** Кешувати cluster cards, оновлювати тільки змінені
5. **FIX G-02:** Підключити `muted_clusters` до AudioEngine
6. **FIX P-04:** `add_heat()` — ітерувати тільки bounding box
7. **FIX C-01:** Видалити dead code (harmonic_mix, boundary helpers, unused Cluster methods)

### Низький пріоритет (при нагоді)
8. Rename `_nb4` → `_nb8`
9. Виправити іконки інструментів в UI
10. Зберігати settings між сесіями
11. Візуальний feedback для catalyst events
12. Performance optimization для великих гридів (P-01, P-02, P-03)
