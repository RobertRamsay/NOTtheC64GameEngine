# NOTtheC64GameEngine — Claude Code guide

A Doom / Quake / early-Unreal style 3D engine (plus 2.5D and 2D modes) in
GameMaker (GML) by Bob / Polytricity Ltd. The only limits: **every pixel is one
of the 16 Pepto C64 colours** and **every texture / tile / sprite frame is at most
16 x 16**. It has a built-in **dual-SID tracker** (6 reSID voices + one ~11 kHz
PCM channel). The full design is in `docs/ENGINE_DESIGN.md`; read it first.
The Level Editor, enemies / things and the Creature Modeler (rigged,
pre-animated template creatures with mesh, bone and curve editing) are specified
in `docs/CONTENT_TOOLS.md`.

Sibling projects we borrow from (read-only, never edit them from here):
`D:\POLYTRICITY\PROJECTS\PIXELL3D\CORE\PIX3LL3D` (CRT, editor pieces),
`D:\POLYTRICITY\C64DevMachine_GIT\C64DevMachine_win.yyp` (sid64 reSID extension,
Music Maker tracker), `D:\POLYTRICITY\ADAM` (play-queue streaming, tracker UX).

## Two programs: Editor and Player (design doc §0)

The **Editor** (what people make games with) and the **Player** (the runtime that
ships with every exported game) are separate programs built from this one
project. `Default` config = Editor, `Player` config = Player, with `NTC64_EDITOR`
true / false (`scr_build`).
- **Engine scripts never call Editor scripts.** Editor -> engine is fine; engine -> editor never.
- The Player only reads a **game pack** (data, versioned by `NTC64_PACK_VERSION`). It never runs author code and never opens file dialogs.
- Any change to the pack format goes in the editor's writer and the Player's reader in the same commit.

## Golden rules (Bob's conventions — always follow)

- **Initialise every instance variable in `obj_engine` Create** (arrays, structs, flags). Never rely on `variable_struct_exists` / `variable_instance_exists`. For data read from JSON, use `struct[$ "key"]` and `is_undefined` / `is_array` / `is_string`.
- **No ternary / shorthand if** (`a ? b : c`). Always full `if { } else { }`.
- **Write hex as `0xff`**, never `$ff` (at the start of an array literal it parses as a struct accessor).
- **Never name a local `x` or `y`** (built-in instance variables). Use `_px`, `_wy`, etc.
- Allman braces, 4-space indent, `_underscore` locals, `UPPER_CASE` macros.
- **Never output a non-Pepto colour into the game image.** Everything the player sees goes through `rt_world` -> `sh_pepto_lock`. Editor UI drawn in Draw GUI is exempt.
- **Never accept a texture bigger than 16 x 16** (`TEX_MAX`). World textures must be a power of two on each side (texture repeat).
- Audio stays reSID-faithful: the tracker produces per-frame SID register writes; never "fake" a SID sound in GML for game output.
- GPL v2 (reSID). Keep licence notices for anything borrowed.
- One feature per commit, clear message. When handing Bob code to paste, use **FIND:** / **REPLACE with:** blocks.

## How to build and check

- Compile with Igor: `powershell -File tools\build.ps1` (Windows VM build into `%TEMP%`, prints the error count). `-Run` runs the game; `-Shot <png>` runs the auto-screenshot self-test (see design doc §10) and quits. Iterate until there are **zero errors**.
- Bob does the hands-on checks in the running game; end each task with exactly what to press / look at to verify.

## Layout

| Resource | Role |
|---|---|
| `objects/obj_engine` | The only object. Create = all state, Step = input + player, Draw = 3D into `rt_world` + lock pass, Draw GUI = present + debug text, CleanUp = free everything. |
| `scripts/scr_ui` | Immediate-mode UI kit (Draw GUI): button, toggle, slider, choice, tabs; C64-blue Pepto style, scales with the window. The Editor grows on it. |
| `scripts/scr_menu` | Options menu (Esc or the MENU button, pauses the game): GAME (resume, restart, Editor, quit), DISPLAY (fullscreen, window size, dither), CRT (scanlines off / progressive / interlaced, blur, curvature ...). |
| `extensions/ntc64fx`, `tools/ntc64fx` | Our own native DLL (not GPL): error-diffusion dithering to Pepto (Floyd-Steinberg, Atkinson, Sierra Lite, Jarvis). Build line in `tools/ntc64fx/build.txt` (Zig in tools/zig). |
| `scripts/scr_settings` | settings.ini: fullscreen, window size, dither, every CRT value. |
| `scripts/scr_build` | `NTC64_EDITOR` (per build config), `NTC64_VERSION`, `NTC64_PACK_VERSION`. |
| `scripts/scr_pepto` | Pepto palette: `pepto_colour`, `pepto_nearest`, `pepto_uniform_array`, `pepto_is_exact`. |
| `scripts/scr_tex` | Index-image textures (<= 16 x 16) -> GameMaker sprites; procedural test set. |
| `scripts/scr_level` | Level JSON v1: defaults, `level_load` / `level_save`, a small polygon builder (`lb_*`), `world_test_level()`. |
| `scripts/scr_world` | Bake a level into the runtime world: sector loops from edges, slope planes, frozen buffers per sector group and texture, moving-plane buffers, blockmap; sector / height / edge queries. |
| `scripts/scr_tri` | Ear clipping with holes, for floors and ceilings. |
| `scripts/scr_mover` | Doors, lifts, crushers, floor / ceiling movers; edge actions (use / walk / shoot) on tags. |
| `scripts/scr_vis` | Portal visibility flood with screen-rect clipping. |
| `scripts/scr_pawn` | The first-person character ("pawn", so it is never confused with the Player program): camera, circle-vs-edge collision with sliding, use and shoot traces. |
| `datafiles/levels` | Level JSON included with the game (`test.json`, written by `build.ps1 -SaveLevel`). |
| `scripts/scr_render` | Render targets, world pass, palette-lock pass, present (+ CRT), auto-screenshot. |
| `scripts/scr_postfx` | CRT parameters and uniforms (from PiX3LL3D `POSTFX_system`). |
| `scripts/scr_audio` | Audio core (engine, ships in the Player): dual-SID + PCM stream through one play queue, F9 test, `-Shot` audio self-test. |
| `extensions/sid64` | reSID DLL (GPL v2). Source + build line in `tools/sid64` (built with `tools/zig`, Zig 0.13.0, git-ignored). |
| `shaders/sh_world` | Texture x light x distance falloff, alpha test. |
| `shaders/sh_pepto_lock` | Nearest Pepto colour + 4x4 Bayer dither between the two nearest. |
| `shaders/sh_crt` | PiX3LL3D CRT pass. |

## Keys

WASD move, mouse look (click to capture, Tab / Esc to release), E use, Ctrl (or click
while captured) shoot, Space jump (Space / C fly up / down in noclip), N noclip, F2 palette/texture
strip, F5 dither, F6 CRT, F7 palette lock on/off (debug only), F8 portal culling on/off,
F9 audio test (dual SID + PCM), F4 / Shift+F4 dither mode, F11 fullscreen, Esc Options menu, F1 debug text.
