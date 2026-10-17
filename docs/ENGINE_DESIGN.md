# NOTtheC64GameEngine — design

A Doom / Quake / early-Unreal style 3D engine (with 2D and 2.5D modes) written in
GameMaker (GML), by Bob / Polytricity Ltd. Its **only** artistic limits:

1. **Colour:** every pixel on screen is one of the 16 **Pepto** C64 colours.
2. **Texture size:** every tile / texture / sprite frame is **at most 16 x 16 pixels**.

Everything else (resolution, polygon count, lights, number of sectors, number of
textures) is free. It also has a built-in **dual-SID tracker**: 6 SID voices
(two reSID chips) + one ~11 kHz 8-bit sample channel, "a SID at capacity".

It will not run on a real C64 / C64 Ultimate. The *music* is the part that
should stay faithful to the hardware: songs must sound right through reSID, and
should stay exportable to a real dual-SID setup later.

---

## 0. Two programs: the Editor and the Player

NOTtheC64GameEngine is **two separate programs**, the same split as Doom's
editors vs. the Doom exe:

| | **Editor** | **Player** |
|---|---|---|
| What | The tool people make games with: map editor, texture / pixel editor, SID tracker, game logic, test play. | The small runtime that **ships with every game** made with the editor. |
| Who builds it | Us (Polytricity), released to users. | Us, **prebuilt once per engine version**, carried inside the Editor. Users never need GameMaker. |
| Contains | Engine core + all editor code. | Engine core only: renderer, palette lock, collision, game logic, audio (sid64), game-pack loader. No editor code paths, file dialogs or tool UI. |
| Reads | Project files (`.ntc64proj`, editable, JSON). | One **game pack** (`game.ntc64`) next to the exe: levels, textures, songs, logic, settings — data only, never code. |

**Export** (Editor -> "Build game"): copy the prebuilt Player (exe, data file,
`sid64.dll`), write `game.ntc64` from the project, add the licence files, and
zip it or make an installer. Same model as ADAM: a fixed engine plus a data block.

### Rules this puts on the code
* **Engine core never calls editor code.** Scripts are split into `Engine` (shared),
  `Editor` (editor only) and a thin per-program boot. The editor may call the
  engine; never the other way round. Test play in the editor runs the *same*
  engine core, fed from the project in memory instead of a pack file.
* The **game pack is a versioned contract** (`NTC64_PACK_VERSION`). A Player must
  load every pack version up to its own; the editor writes the current one.
  The format will be specified in `docs/GAME_PACK.md` before the first exporter.
  Any change to it is made in both places: the editor's writer and the Player's reader.
* Anything a game can do at run time (sector specials, doors, triggers, music
  cues, SFX) must be **data-driven** from the pack. Game authors cannot add code
  to the Player.

### How it is built (GameMaker)
* **One GameMaker project, two build configurations:** `Default` = Editor and
  `Player`. The macro `NTC64_EDITOR` (in `scr_build`) is `true` in Default and
  `false` in Player, so the boot code picks which program it is.
* `powershell -File tools\build.ps1 -Config Player` builds the Player. The
  Editor's release script copies that build into the Editor's included files
  (`datafiles/player/`) so Export has something to copy.
* Alternative if the Player ever needs to be smaller or cleaner: move `Engine`
  scripts into a GameMaker local package shared by two projects. The rules
  above keep that move cheap.

### Open question: GPL and the GameMaker runner
reSID is GPL v2, so every exported game's Player contains GPL code. Two
consequences to settle before the first public release:
1. Exported games need the GPL text and the Player's source (or a written offer
   for it). The game's own data (levels, art, music in the pack) is loaded at
   run time and stays the author's.
2. The Player is a **proprietary GameMaker runner loading a GPL DLL**. Whether
   distributing that combination is allowed under GPL v2 needs a proper licence
   check. If it is not allowed, the options are:
   * run reSID in a separate small GPL helper process the Player talks to;
   * or swap in a SID core under a permissive licence.

   C64 Dev Machine already ships sid64 the same way, so the answer covers both.

---

## 1. Decisions (October 2026)

| Topic | Decision | Why |
|---|---|---|
| Tool | GameMaker LTS 2026, GML only, Windows first | Same toolchain as ADAM, PiX3LL3D, C64 Dev Machine; scenes kept trim. |
| Level geometry | **Sectors + portals** (Doom/Build style, rendered as true 3D) | Easy to edit, cheap in GameMaker, gives stairs / lifts / room-over-room. |
| Colour lock | One **post pass** (`sh_pepto_lock`) over the low-res frame | Nothing can leak a non-Pepto colour; lighting / fog can be computed freely. |
| SID audio | Native **reSID** through the `sid64` GameMaker extension (forked from C64 Dev Machine) | Faithful 6581/8580 output is not realistic in GML next to a 3D renderer. |
| Licence | **GPL v2** accepted (reSID is GPL v2) | Engine and games that ship reSID are released under the GPL. |
| Sample channel | **Native 8-bit PCM** mixed inside the DLL (not $D418) | Simple, identical on 6581/8580. $D418 mode can be added later as an option. |

---

## 2. Frame pipeline

```
 Step: input -> player move (sector collision) -> game logic -> music tick (once per 50 Hz frame)
 Draw:
   rt_world  (RENDER_W x RENDER_H, depth buffer)     3D: static sector vertex buffers, sh_world
                                                     (texture x sector light x distance falloff)
             + billboards / HUD (2D, before the lock)
   rt_locked (same size)  <- sh_pepto_lock            nearest Pepto colour, optional 4x4 Bayer
                                                     dither between the two nearest colours
 Draw GUI:   rt_locked -> window through sh_crt       letterboxed, CRT optional (F6)
             editor UI / debug text on top (not part of the game image)
```

* **Internal resolution** defaults to **320 x 200** (Doom's and the C64's). It is a
  macro (`RENDER_W`, `RENDER_H`); 384 x 272 (full PAL border) or 640 x 400 work too.
* The game image is never drawn through `application_surface` (auto-draw is off);
  it is shrunk to the render size so it costs nothing.
* **Lighting** is computed in full colour (sector light 0..1, distance falloff
  like Doom's diminishing light) and then snapped to Pepto. Dark scenes collapse
  into black / dark grey / brown / blue — that is the look. Dithering softens it.
* Later: authored **light ramps** per colour (a Doom COLORMAP equivalent, 16 x 32
  table) to override the automatic nearest-colour choice where it looks wrong.

## 3. Coordinates and units

* **+Z is up**, X east, Y south (GameMaker's 2D Y). Camera uses
  `matrix_build_lookat(..., 0, 0, 1)` and a projection with **negative FOV and
  aspect** (the usual GameMaker 3D fix-up).
* **64 world units = one 16 px texture repeat** (`TEX_WORLD`, so 1 texel = 4 units).
* Player: eye height 48, step-up 24, minimum headroom 56.

## 4. World model (sectors + portals)

A level is a JSON-able struct:

```
level = {
    name, version,
    sectors: [
        {
            pts:   [x0, y0, x1, y1, ...],     // polygon, any winding; edge i = pt i -> pt i+1
            floor, ceil,                       // heights (world units)
            ftex, ctex,                        // texture names
            light,                             // 0..1
            edges: [ { tex, portal } , ... ]   // one per edge; portal = neighbour sector or -1
        }, ...
    ],
    things: [ { type, x, y, angle, ... } ]     // later: player start, monsters, items, lights
}
```

* A **solid edge** draws a full wall floor -> ceil.
* A **portal edge** draws a *lower* wall when the neighbour's floor is higher and an
  *upper* wall when the neighbour's ceiling is lower. Each sector only draws the
  faces that look into itself, so shared edges never draw twice.
* Room-over-room (Unreal / Build style) comes from portals between sectors that
  overlap in plan but not in height — the sector lookup must test height as well
  as the polygon (planned, not in the skeleton).
* Floors / ceilings are triangulated **once at load** (fan for convex sectors in
  the skeleton; ear clipping for concave ones is next).
* **Static geometry is baked into one frozen vertex buffer per texture**
  (`vertex_freeze`) — a few dozen `vertex_submit` calls per frame for a whole
  level. Doors / lifts are separate small buffers with their own matrix.
* **Visibility** (later): portal flood from the camera's sector with a screen-rect
  clip, then only submit buffers of visible sectors (buffers per sector group).
* Sloped floors / ceilings (Build / Quake look): per-sector plane `(z, dz/dx, dz/dy)`
  — planned.

## 5. Textures and sprites

* Textures are **index images**: each pixel is a Pepto index 0..15 or transparent.
  They are turned into tiny GameMaker sprites with `sprite_create_from_surface`
  (one texture page each) so `gpu_set_texrepeat(true)` can tile them across walls.
* World textures must be **1, 2, 4, 8 or 16** pixels on a side (power of two, for
  repeat). Entity sprite frames may be any size up to 16 x 16.
* PNG import (next): quantise to Pepto (nearest, optional dither), reject or crop
  anything over 16 x 16, slice sheets into 16 x 16 cells (PiX3LL3D
  `tileset_import` does the slicing).
* The pixel editor comes from PiX3LL3D's `PIXEL_editor` with DB32 swapped for the
  16 Pepto colours and painting locked to indices.
* **Creatures and enemies are low-poly 3D models**, rigged and animated, built in
  the Creature Modeler (`docs/CONTENT_TOOLS.md` §C). Their faces are flat Pepto
  colours or <= 16 x 16 textures. A 16 x 16 sprite is too small to be a monster
  at 320 x 200, but a model has no size limit.
* Small things (pickups, effects, decorations) can be camera-facing **billboards**:
  1/8/16 directions of <= 16 x 16 frames, drawn into `rt_world` before the lock.

## 6. Modes

| Mode | What it is |
|---|---|
| **3D** | The sector renderer above, free mouse-look. |
| **2.5D** | Same renderer, pitch locked to 0 and Doom-style movement (no jumping/looking up). |
| **2D** | Tile maps of <= 16 x 16 tiles drawn orthographically into `rt_world`; same palette lock and CRT. |

## 7. Audio — the SID tracker

### Engine
* **`sid64` extension** (from `C64DevMachine_GIT/tools/sid64`, reSID + reSID-fp,
  per-chip 6581 / 8580). Fork it into `tools/sid64` here, then:
  1. `sid64_render_dual(...)`: clock both chips *and* the PCM channel and mix
     (mono or stereo L/R per chip) **inside C++** — removes the per-sample
     `buffer_peek/poke` mix that C64 Dev Machine does in GML.
  2. A **PCM channel**: 8-bit signed samples at ~11025 Hz, note-pitched,
     volume 0..15, mixed after the SIDs.
  3. Fix `sid64_settle` looping forever when `clock` returns 0.
* GameMaker side: one `audio_create_play_queue` (s16, 44100 Hz), ~80 ms chunks,
  ~240 ms queued ahead, refilled from the Async Audio Playback event (ADAM's
  `music_preview_*` pattern).
* The tracker "player" runs in GML **once per 50 Hz PAL frame** and writes a
  32-byte register record per chip per frame (`render_log` format) — the C64 Dev
  Machine's `scr_sid64_sim` already does this frame-exactly.

### Tracker
* Data model and instrument language from C64 Dev Machine's Music Maker:
  GoatTracker-style instruments with pitch / pulse / filter tables
  (`scr_instrument_parse`), shared pattern pool, per-voice order lists with
  transpose, a digi lane (`scr_music_digi`).
* Widened from 3 to **6 voices + 1 sample lane**.
* Screen layout ideas from ADAM's Music page (song timeline, loop library,
  step editor).
* Exports: `.sid` (2SID PSID v3, second chip at $D420/$D500), `.wav`; game
  runtime plays the song data directly.
* Sound effects: the same voices, stolen per channel with priorities (classic C64
  SFX-over-music), so music + SFX together never exceed 6 voices + 1 sample.

## 8. Borrowed code — map

| From | Take | Status |
|---|---|---|
| PiX3LL3D `shaders/sh_crt` | CRT post pass | **in the skeleton** |
| PiX3LL3D `POSTFX_system` | post pipeline + slider panel | pipeline in; panel later |
| PiX3LL3D `PIXEL_editor`, `tileset_import`, `MENU_system`, `GRID_system`, `UNDO_system`, `scene_save` | editor | later |
| C64 Dev Machine `scr_c64_pepto_colour` | Pepto values | **in the skeleton** (`scr_pepto`) |
| C64 Dev Machine `extensions/sid64`, `tools/sid64` | reSID DLL | next milestone |
| C64 Dev Machine `scr_sid64_sim`, `scr_sid64_audio`, `scr_instrument_parse`, `scr_sound_editor_*`, `scr_music_digi`, `scr_sound_editor_export_sid` | tracker | next milestones |
| ADAM `scr_music` (`music_preview_*`) | play-queue streaming | next milestone |
| ADAM `scr_ws_music` | tracker UX ideas | later |
| C64NoCode `scr_sid` (SID ADSR rate table, noise LFSR, 6502 player emitter), `scr_patch` (sync / ring mod / filter routing), `scr_digi` (WAV import, 4-bit $D418 NMI player), `scr_ws_music` PSID export | SID reference + C64-side export | reference; port where Dev Machine lacks it |

## 9. Milestones

The content tools (level editor, enemies, creature modeler) are specified in
`docs/CONTENT_TOOLS.md`. Steps marked ‖ can run in parallel once the step
before them is done.

1. **Skeleton** ✔: project, Pepto palette, render pipeline, palette lock + dither,
   CRT, walkable test level, auto-screenshot self-test, Editor / Player configs.
2. **Audio core** (blocked: needs a C++ compiler, Zig 0.13 or mingw g++):
   sid64 fork with dual mix + PCM, play-queue streaming.
3. **World runtime:**
   * level JSON v1 (vertices / sectors / two-sided edges / things) with load and save;
   * ear clipping, slopes;
   * radius collision with sliding;
   * movers (doors, lifts, crushers), edge actions and tags;
   * portal visibility.
4. **Editor shell** (CONTENT_TOOLS §D): UI kit, pages, viewport widgets (camera,
   grid, gizmos, picking), command undo, project folder.
5. ‖ **Level Editor** (§A): plan view, 3D Build-style editing, drawing tools,
   surfaces, specials, things placement, validation, test play.
5. ‖ **Creature runtime + templates** (§C2, §C7): skinned mesh format, `sh_skin`,
   clip sampling and crossfade, GML-generated template creatures. The stock
   humanoid is the first enemy body.
6. **Enemies runtime** (§B3): sector-graph navigation, senses, behaviour presets,
   attacks, projectiles, damage, items, weapons.
7. ‖ **Creature Modeler** (§C3–C6): mesh edit, paint, rig, dope sheet + curve
   editor, events.
7. ‖ **Enemy Editor** (§B2) and **things** (§B1 complete).
7. ‖ **Tracker** (§7): 6+1 voice data model, player sim, editor page, `.sid` /
   `.wav` export. Needs step 2.
8. **Texture tools:** Pepto pixel editor, PNG import.
9. **Game pack + Export:** `docs/GAME_PACK.md`, pack writer (Editor) and reader
   (Player), Player boot, "Build game", licence bundle.
10. **Modes:** 2.5D and 2D.

## 10. Self-test

`powershell -File tools\build.ps1 -Shot out.png [-Pose "x,y,z,yaw,pitch"]` sets
`NTC64_AUTOSHOT` and runs the game: after 30 frames it saves the palette-locked
frame (and `out.png_raw.png`, the frame before the lock), checks every pixel of
the locked frame is a Pepto colour, prints `AUTOSHOT ... ok` or `... FAIL` and
quits. `NTC64_AUTOSHOT_SWATCHES=1` adds the F2 debug strip (16 swatches that must
come through the lock unchanged, plus every texture). Shots: `docs/shots/`.

### Palette lock notes (learned the hard way)
* Colour distance is RGB weighted **2:4:3**. Luma weights (0.3 / 0.59 / 0.11)
  under-count red and blue errors, and dim greys snap to blue / brown.
* Dithering picks the best **pair** out of all 120 (segment closest to the true
  colour, plus `PAIR_PENALTY` x the pair's spread). Pairing the nearest colour
  with a partner is not enough: dim red is black + red, and its nearest
  colour is brown.
