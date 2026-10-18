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

* **Internal resolution** is **320 x 200** (Doom's and the C64's). It is a
  macro (`RENDER_W`, `RENDER_H`), and Bob is happy with 320 x 200. 640 x 400 is the
  most it should ever be, if a game pack setting for it is added later.
* **The window is free:** windowed at x1..x6 (640 x 400, 1280 x 800 ...),
  drag to any size, or fullscreen (F11). The image is always letterboxed and
  scaled up, so the pixels stay big.
* **Options menu** (Esc or the MENU button; `scr_menu`, in both Editor and
  Player). It pauses the game and has three tabs:
  * **Game:** resume, restart, Editor, quit.
  * **Display:** fullscreen, window size, the Pepto dither amount.
  * **CRT:** scanlines off / progressive / interlaced, then scanline depth,
    composite blur, curvature, mask, colour fringe, glow, vignette, flicker,
    brightness / contrast / saturation.

  Settings are saved per machine in `settings.ini` (`scr_settings`).
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

A level is **JSON v1** (`scr_level`, `docs/CONTENT_TOOLS.md` §A6), read by
`level_load` and written by `level_save`. Missing keys get defaults, so older
files keep loading. The test level is `datafiles/levels/test.json`, written from
`world_test_level()` with `build.ps1 -SaveLevel datafiles\levels\test.json`.

```
level = {
    version: 1, name,
    settings: { music, sky, fog, gravity, par, next, secret_next },
    vertices: [ [x, y], ... ],
    sectors:  [ { floor, ceil, ftex, ctex, light, tag, special,
                  fslope: { edge, rise }, cslope: { edge, rise } } ],
    edges:    [ { v0, v1, front, back, flags, action,
                  sides: [ { upper, middle, lower, ox, oy, sx, sy } x 2 ] } ],
    things:   [ { type, x, y, z, angle, tag, flags } ]
}
```

* **Edges are stored once** (Doom linedefs). The front sector is on the right of
  `v0 -> v1` on the plan (Y down), the back on the left; `back -1` is a solid
  wall. `sides[0]` faces the front, `sides[1]` the back, so a portal's two faces
  carry their own textures. Sectors have no polygon of their own: `world_bake`
  traces their **loops** from the edges (outer loops plus holes, e.g. a pillar).
* A **one-sided** edge draws its middle texture floor -> ceil. A **portal** draws
  a *lower* wall where the other floor is higher and an *upper* wall where the
  other ceiling is lower; each side draws only the faces that look into its own
  sector. A middle texture on a portal is **see-through** (grates; alpha test in
  `sh_world`); `EDGE_BLOCK` makes it solid to movement.
* **Slopes:** a hinge edge plus a rise. The plane is at the sector's floor (ceil)
  height along the hinge and `rise` higher at the sector's furthest point; it is
  baked to `z = a*x + b*y + c` and used by the renderer, collision and movers.
* **Triangulation:** ear clipping (`scr_tri`), holes bridged into their outer
  loop first (Eberly), so concave sectors and sectors with holes work.
* **Static geometry** is frozen once per **sector group** (a few neighbouring
  sectors) and texture, a few dozen `vertex_submit` calls per frame.
* **Movers** (door, lift, crusher, floor / ceiling, `scr_mover`) change a
  sector's floor / ceiling offset. Each plane's travel is worked out at bake time
  from the actions that target it. The moving flat, and the walls whose visible
  edge *is* that plane (a door's face, a lift's front), are small separate
  buffers drawn with a translate matrix. Every other wall next to it is static and
  baked over the whole travel; the part beyond the plane is hidden behind it.
* **Edge actions**: trigger `use` (E) / `walk` (centre crosses the edge) /
  `shoot` (hitscan), once or repeat, effect on every sector with the action's tag
  (tag 0 = the edge's back sector, like Doom's door lines).
* **Visibility** (`scr_vis`): flood from the camera's sector through portals
  that face the eye. Each portal opening (as it is now; closed doors stop it) is
  near-clipped, projected and clipped to the window of the sector it is seen
  from. Only groups holding a reached sector, and moving planes next to one, are
  drawn. F8 turns it off; `build.ps1 -NoVis` shots must come out identical.
* **Collision** (`scr_pawn`): circle against edges via a 128-unit blockmap,
  sliding, step / headroom rules on two-sided edges, floor / ceiling height
  under the whole circle (Doom's floorz / ceilingz). Lifts carry the pawn; doors
  reopen and crushers back off when they reach it (no damage yet).
* Room-over-room: `world_sector_at` takes the feet height and picks the highest
  floor at most a step above them where sectors overlap in plan. Rendering
  and portals already work in 3D; nothing in the test level uses it yet.

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
* **Two views of one song** (Bob, October 2026): the horizontal bar tracker
  (time runs left to right, one lane per voice) and a classic **vertical
  row-based tracker** (OctaMED / ProTracker / GoatTracker style: rows run down,
  one column per voice + the sample lane, note / instrument / effect cells).
  Both edit the **same** data model (patterns, order lists, instruments), so
  either view can be used at any time and switching never converts anything.
  Build the horizontal view first; the vertical view is a second editor over the
  same model, not a separate format. The Player only sees the song data.
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
3. **World runtime** ✔ (§4):
   * level JSON v1 (vertices / sectors / two-sided edges / things) with load and save;
   * ear clipping, slopes, see-through middle textures;
   * radius collision with sliding;
   * movers (doors, lifts, crushers, floor / ceiling), edge actions and tags, use key;
   * portal visibility.

   Left for later: damage from crushers (needs §B3), the rest of the §A4
   specials (stairs raise, light change, teleport, exit, secret, music change,
   scrolling floor), texture pegging, room-over-room in the test level.
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

More switches for the world runtime:
* `-Frames n` takes the shot at frame n instead of 30.
* `-Use` presses the use key at frame 2 (open a door, call a lift).
* `-Walk "f36,t-90,f70,e,w70,f200,p"` drives the pawn *with collision* (a pose
  then only sets the start): `f/b<n>` forward / back n frames, `l/r<n>` strafe,
  `w<n>` wait, `t<deg>` turn left, `e` use, `s` shoot, `p` logs
  `WALK frame: x, y, z sector last-action`.
* `-NoVis` turns portal culling off; a shot must come out byte-identical with and
  without it.

Checks used for milestone 3 (`m3_*` shots):

| What | Command (after `-Shot x.png`) | Expect |
|---|---|---|
| Stairs into the hall | `-Walk "f200,p" -Frames 220` | `896, 256, 64 sector 5` |
| Door blocks, then opens | `-Walk "f36,t-90,f70,p,e,w70,f200,p" -Frames 400` | `240, 500` then `240, 948 sector 10` |
| Slide along a wall | `-Walk "t60,f120,p" -Frames 130` | `336, 12` |
| Lift ride | `-Pose "1024,600,64,270,0" -Walk "e,w40,f20,w160,p" -Frames 230` | z `192`, sector 7 |
| Ramp | `-Pose "200,864,0,180,0" -Walk "f60,p" -Frames 70` | `-40, 864, 26` |
| Shoot the target | `-Pose "850,330,64,0,0" -Walk "s,w50" -Frames 60` | `ACTION shoot edge 26: floor`, platform up |
| Culling is exact | any pose, with and without `-NoVis` | identical PNGs |

### Dither modes (Options > Display, F4; sheet in `docs/shots/dither_modes.png`)
* **Threshold patterns:** these run per pixel in `sh_pepto_lock` and are free.
  The modes are Bayer 4x4 (default), Bayer 8x8, checker, interlace lines,
  lines + checker, white noise (static or animated) and interleaved-gradient
  "blue" noise (static or animated).
* **Error diffusion:** Floyd-Steinberg, Atkinson, Sierra Lite and
  Jarvis-Judice-Ninke.
  * These can't run per pixel, so the frame is read back, dithered in the
    `ntc64fx` DLL (serpentine scan) and uploaded again.
  * At 320 x 200 that is well under a millisecond plus one readback.
  * Expect "crawling" patterns while the camera moves: that is the nature of
    error diffusion.
  * Without the DLL these modes fall back to Bayer 4x4.
* **Dither amount** (0..1) scales the pattern or the diffused error. 0 is the
  plain nearest colour.

### Palette lock notes (learned the hard way)
* Colour distance is RGB weighted **2:4:3**. Luma weights (0.3 / 0.59 / 0.11)
  under-count red and blue errors, and dim greys snap to blue / brown.
* Dithering picks the best **pair** out of all 120 (segment closest to the true
  colour, plus `PAIR_PENALTY` x the pair's spread). Pairing the nearest colour
  with a partner is not enough: dim red is black + red, and its nearest
  colour is brown.
