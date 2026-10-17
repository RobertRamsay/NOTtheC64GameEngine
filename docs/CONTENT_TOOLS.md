# NOTtheC64GameEngine — content tools

This document specifies the three Editor tools that make up most of a game:

* **A. Level Editor:** sectors, surfaces, specials, things.
* **B. Things and Enemies:** what can be placed in a level and how enemies behave.
* **C. Creature Modeler:** low-poly creatures from rigged, pre-animated templates,
  with mesh, bone and curve editing.

All three live in the **Editor**. Their output is **data** in the game pack,
which the **Player** reads (see `ENGINE_DESIGN.md` §0). Game authors never write
code. Everything a level or enemy does is chosen from presets and parameters.

The engine's two limits apply everywhere:
* every pixel on screen is a Pepto colour;
* every texture is at most 16 x 16.

A 3D model is not a texture, so creatures can be any size on screen. Their
*surfaces* are flat Pepto colours or <= 16 x 16 textures. This is why creatures
are 3D models and not Doom-style sprites: a 16 x 16 sprite is too small to be
a monster at 320 x 200.

---

## A. Level Editor

### A1. Views
* **2D plan view** (Doom Builder style): grid, zoom and pan, sectors, edges,
  vertices and things. Everything is drawn in Pepto colours with editor
  highlights on top.
* **3D view** (Build style): fly through the level as it will look in the
  Player (same renderer and palette lock), point at a surface and edit it in place.
* **Split view:** plan and 3D side by side. A selection in one shows in the other.
* **Test play** from the 3D camera or from the player start. This runs the
  real engine core with the level in memory; Esc goes back to editing.

### A2. Drawing geometry
* **Draw sector:** click vertices and close the loop. The editor:
  * splits existing edges where the new shape touches them;
  * joins shared edges as portals automatically (as `world_auto_portals` does today);
  * inherits heights, textures and light from the sector the shape was drawn in.
* **Rectangle and circle (n-gon) tools**, plus **draw inside a sector** to make
  pillars, pits, platforms or holes.
* **Concave sectors are allowed:** floors and ceilings are ear-clipped at load.
* **Move, rotate, scale and flip** vertices, edges, sectors and selections, snapping
  to the grid (1, 2, 4 ... 256 units) or vertex snap.
* **Split edge, merge vertices, join sectors, split sector by line, delete with
  heal.** Delete with heal removes a vertex or edge and repairs the neighbouring
  sectors.
* **Stairs builder:** select a run of sectors and pick a step height and
  direction. **Arch / curve builder:** subdivides an edge into a curve.
* **Prefabs:** save a selection (geometry and things) and stamp it anywhere.
  Copy and paste between levels.
* **Room-over-room:** sectors may overlap in plan if their height ranges don't.
  The plan view has a **layer / height filter** so you can see each storey.

### A3. Surfaces
* **Per sector:**
  * floor height, ceiling height, floor and ceiling texture;
  * **slope:** pick a floor or ceiling edge and set its rise;
  * light level 0..1, light effect (none, flicker, strobe, glow, candle, fade
    cycle), sky ceiling;
  * damage floor, friction;
  * ambient sound;
  * tag.
* **Per edge (wall):**
  * **upper / middle / lower textures**. Middle textures can be see-through, for
    grates and fences (the alpha test is already in `sh_world`);
  * per-texture **offset X/Y, scale and peg**: peg to the floor or ceiling, or
    keep world-aligned;
  * an **action**, see A4;
  * blocks player, blocks monsters, blocks sound, secret, impassable;
  * a mirror flag (planned).
* **3D-view surface editing** (Build keys):
  * PgUp / PgDn raise or lower the floor or ceiling under the cursor;
  * arrow keys pan the texture, shift+arrows scale it;
  * click to copy a texture and right-click to paste it;
  * brackets change the light;
  * every edit lands in undo.
* **Texture browser:** every project texture as a 16 x 16 swatch with search
  and recently used. Double-click opens it in the pixel editor (Pepto-locked).

### A4. Specials and actions (data, no code)
* **Sector specials:**
  * door (up/down, speed, wait time, key needed);
  * lift / platform;
  * crusher;
  * floor or ceiling mover (to the next neighbour's height, by an amount, or to a set height);
  * stairs raise;
  * light change;
  * teleporter destination;
  * exit (normal or secret);
  * secret area;
  * music change;
  * scrolling floor.
* **Edge actions:** a trigger plus an effect on a **tag**.
  * Triggers: use, walk over, shoot, monster cross, or once vs. repeatable.
  * Effects: any special above applied to every sector or thing with that tag;
    also teleport, spawn, show message, play sound, end level.
* **Trigger volumes** (things, see B) do the same for areas, not lines.
* **Level rules** (later): ADAM-style WHEN / DO cards for level scripting without
  code. Examples: "when all things tagged 3 are dead, open door tag 4"; "when
  the player enters sector tag 7, start wave 2".
* Runtime: movers are separate small vertex buffers with their own matrix
  (`ENGINE_DESIGN.md` §4). Static geometry stays frozen.

### A5. Level settings and checks
* **Level settings:**
  * name and music (a tracker song);
  * sky (a 16 x 16 texture tiled on a dome, or a flat Pepto colour);
  * fog / falloff distance;
  * gravity;
  * par time;
  * next level and secret next level.
* **Episodes:** an ordered list of levels with intermission text.
* **Validation (Check button):**
  * unclosed sectors, overlapping edges, zero-height sectors;
  * missing textures;
  * player start missing or stuck;
  * tags with no target, unreachable exits;
  * enemies inside walls.

  Clicking an error jumps to it.
* **Undo / redo** for everything: command-based, so big maps don't clone the
  whole world the way PiX3LL3D's snapshot undo does.

### A6. File format
* Each level is plain JSON in the project (`levels/<name>.json`), human-readable,
  with versioned fields and missing keys filled with defaults. The struct shape
  already in `scr_world` grows into:
  * `{ version, name, settings, vertices, sectors, edges, things }`.
  * **Edges** are stored once, with a front and back sector, as in Doom
    linedefs, so a portal's two sides can carry different textures.
* The game pack stores the same data. The engine bakes it at level start; nothing
  is pre-baked, so levels stay small.

---

## B. Things and Enemies

### B1. Thing types (placeable in the Level Editor)
Every thing has a position, angle, height offset, tag, and **skill flags**: on
for Easy / Normal / Hard and/or for single player / co-op (later). Types:

| Group | Things |
|---|---|
| Start | Player start, co-op starts (later), teleport destination |
| Enemies | Any **enemy type** (B2). Options: ambush (deaf until seen), patrol path, spawn dormant (woken by a tag) |
| Items | Health, armour, ammo, keys (3 colours), power-ups, weapons, score items |
| Props | Static models from the Creature Modeler (no rig needed), billboard sprites, solid or not |
| Lights | Point light (radius, Pepto tint, effect), baked into vertex light at level start; flicker / pulse animate |
| Sound | Ambient emitter (SID SFX, radius, loop), music zone |
| Logic | Trigger volume, spawner (enemy type, count, wave, tag), waypoint / patrol path node, camera point (cutscenes, later) |
| Effects | Particle emitter (Pepto pixels: sparks, smoke, drips) |

Things show in the plan view as **icons with direction arrows**, and in the 3D
view as their real model or sprite.

### B2. Enemy types: the Enemy Editor
An enemy type is a data record, made in an **Enemy Editor** page:

* **Body:** a creature (C) or a billboard sprite set, collision cylinder (radius,
  height), mass, flying or walking, step height.
* **Stats:**
  * health, speed, turn rate;
  * pain chance, pain time;
  * sight range and field of view, hearing range;
  * reaction time;
  * gib threshold.
* **Behaviour preset** (a data-driven state machine shared by the engine):

| Preset | Does |
|---|---|
| **Melee chaser** | Wakes up, chases, attacks at contact range (zombie / pinky) |
| **Ranged shooter** | Keeps a preferred distance, strafes, fires projectiles or hitscan (imp / trooper) |
| **Hybrid** | Melee up close, ranged further away (baron) |
| **Flyer** | Floats at a height band, swoops (cacodemon / bat) |
| **Charger** | Winds up, then dashes in a straight line (lost soul) |
| **Turret** | Doesn't move, turns and fires (sentry) |
| **Patrol guard** | Walks a waypoint path until alerted |
| **Swarm** | Weak, comes in groups, flocks |
| **Summoner** | Keeps away, spawns other enemy types (arch-vile, lite) |
| **Boss** | Phases at health thresholds; each phase picks another preset and attack set |

* **Attacks** (up to 4 per enemy):
  * melee (damage, reach, arc);
  * hitscan (damage, spread, pellets);
  * projectile (speed, damage, splash radius, gravity, homing, its own model or
    sprite and trail);
  * each attack has a cooldown, a range band and a weight.
* **Animation mapping:** which creature clip plays for idle, walk, run, each attack,
  pain, death (and gib). **Animation events** in the clip (C5) time the hit and
  the projectile release ("fire at frame 12"), so attacks line up with the
  animation.
* **Sounds:** sight, active, pain, death and attack, as SID SFX from the tracker.
* **Drops:** item thing, with a chance.
* **Flags:** counts for kill %, infighting allowed, immune to splash, boss
  (health bar), floats, no knockback.

### B3. Runtime (engine core, the Player has it)
* **Navigation:**
  * enemies path over the **sector graph** (portals with step / headroom limits),
    then steer inside sectors;
  * flyers ignore steps but respect ceilings;
  * no navmesh to bake: the level *is* the graph.
* **Senses:**
  * sight is a ray through portals (a sector walk, cheap);
  * sound is noise flooding through portals from gunfire, blocked by "blocks
    sound" edges, Doom-style.
* **Combat:**
  * damage, knockback, pain, death;
  * corpses stay as the last frame of the death clip;
  * enemies can infight.
* **Budget:** dozens of active enemies at 60 fps. Enemies far away or unseen
  update at a lower rate, and animation is GPU-skinned (C7).

---

## C. Creature Modeler

### C1. Idea
Start from a **template creature** that is already modelled, rigged and animated.
Push its vertices into your own shape, recolour it, and adjust its animations.
Because the skeleton and clips come with it, a new monster can walk, attack and
die minutes after you start. Building from scratch (an empty mesh plus your own
bones) is possible too.

### C2. Templates
Each template has a base mesh (about 150-400 triangles), a skeleton and a
standard clip set. Templates in the same **family** share a skeleton, so clips
can be copied between creatures of that family.

| Template | Skeleton (bones) | Clips |
|---|---|---|
| **Humanoid** | pelvis, spine, chest, neck, head, L/R upper arm, forearm, hand, thigh, shin, foot (17) | idle, walk, run, melee, shoot, pain, death, death-gib, taunt |
| **Brute** (heavy humanoid, long arms) | humanoid family | idle, lumber, slam, throw, pain, death |
| **Quadruped** | pelvis, spine x2, neck, head, jaw, tail x3, 4 x (upper, lower, foot) (21) | idle, walk, trot, pounce, bite, pain, death |
| **Flyer** | body, head, jaw, L/R wing x2, tail x2 (10) | hover, fly, swoop, spit, pain, death-fall |
| **Crawler** (spider / insect) | body, abdomen, head, 6 or 8 legs x 3 (20-26) | idle, scuttle, lunge, pain, death-curl |
| **Serpent** | head, jaw, N segments (8-16) | idle-sway, slither, strike, pain, death |
| **Floater** (blob / eye) | body, jaw, eye, 4 tendrils x 2 (12) | bob, drift, bite, spit, pain, death-burst |
| **Turret / machine** | base, yaw, pitch, barrel | idle-scan, fire, pain, destroyed |
| **Prop** | none or one bone | none (or a spin / sway loop) |
| **Weapon (view model)** | root, slide, trigger, magazine, hands | idle, fire, reload, raise, lower |

Templates are generated **in GML** (`creature_template_humanoid()` and so on),
not loaded from files. This gives two things:
* they always exist, even with no project open;
* enemies can use them before the modeler is finished. A stock humanoid is the
  first enemy.

### C3. Mesh editing
* **Select** vertices, edges, faces or whole bone groups. Box, lasso, grow and
  shrink selection.
* **Move / rotate / scale** with axis lock and grid snap, plus **X-mirror symmetry**
  (on by default for templates).
* **Proportional (soft) editing** with radius falloff: drag a vertex and its
  neighbours follow. This is the quickest way to reshape a template.
* **Extrude, inset, bevel (one step), subdivide face, loop cut, merge, split,
  delete, flip normals, fill hole.**
* **Add primitive** (box, cylinder, cone, sphere, horns / spikes) attached to
  a bone.
* **Polygon counter** with a soft budget: green under 600 triangles, amber under
  1200, red above. Many enemies on screen at once must stay fast.

### C4. Surfaces
* **Every face** is either:
  * a **flat Pepto colour** (fast, and clean flat-shaded lighting), or
  * a **<= 16 x 16 texture** from the project's textures.
* **Paint mode:** click faces with a Pepto colour or a texture, or bucket-fill
  a bone group.
* **UVs:**
  * auto box or cylinder projection per bone group;
  * a simple UV view for nudging texels;
  * textures tile, so a 16 x 16 scale texture can cover a whole flank.
* **Shading:** flat per face (PS1 / early Quake look) or smooth. Lighting and
  fog go through the palette lock like the rest of the world, so the creature
  dithers into shadow.

### C5. Rigging
* **Bone edit mode:** move joints (the mesh follows its bind), change bone lengths
  for new proportions, add, remove or rename bones, re-parent.
* **Skinning:** each vertex has **one bone** by default, which gives rigid
  segments, the Quake / PS1 look, and is very cheap. Optionally it can have
  **two bones with a weight** for smooth elbows and knees.
  * Auto-bind uses the nearest bone segment.
  * **Weight paint** sets the weights by hand.
* **Proportion presets:** sliders that scale bone groups (longer arms, bigger
  head, wider shoulders). The clips still work because they are stored as
  rotations.

### C6. Animation
* **Clips:**
  * a named animation with a length, a loop flag and a speed;
  * channels per bone: **rotation X/Y/Z** (Euler degrees, converted to
    quaternions at runtime) and **position X/Y/Z** (root bone, and any bone that
    needs it). Scale is optional.
* **Dope sheet / timeline:** keys per bone and channel, scrub, play, loop range,
  onion skin (previous and next pose as outlines).
* **Curve editor:** per-channel curves with **step / linear / bezier** keys,
  handles (auto, aligned, free), and copy and paste of keys and curves. Snap
  to frame (30 fps timeline) or free time.
* **Pose mode:** rotate bones directly in the viewport to set keys (auto-key
  toggle). Mirror the pose left / right. Copy a pose and paste it flipped.
* **Events track:** named markers on the timeline, for example `footstep`,
  `hit`, `fire`, `spawn_gib`, `sound:<sfx>`. Enemies and the audio system
  listen for them.
* **Clip tools:** duplicate, mirror (left <-> right), retime, reverse, add a
  procedural loop (breathing or bob), and **import a clip from another creature
  of the same family**.
* **Preview:** the creature walks on a ground grid in the real renderer (palette
  lock, CRT optional). Toggle the collision cylinder and the hit capsules.

### C7. Runtime (engine core, the Player has it)
* **Data:** the mesh is stored once as a frozen vertex buffer in bind pose. Each
  vertex carries its bone index (and the second bone with its weight).
* **GPU skinning** in `sh_skin` (world shader + bones):
  * a bone uniform array of **two vec4s per bone** (a rotation quaternion and a
    translation), up to 32 bones;
  * per frame the CPU only samples the curves and builds 32 bone transforms;
  * the mesh never re-uploads.
* **Blending:**
  * crossfade between clips (0.1-0.25 s);
  * later, upper / lower body layering: shoot while walking.
* **Hit testing:** a capsule per bone, generated from its vertices, for
  damage zones (head = x2). Movement uses the simple cylinder.

### C8. File format
`creatures/<name>.json`:
`{ version, name, template, family, bones: [{ name, parent, head, tail }], verts:
[x, y, z, bone, bone2, w], faces: [{ v: [a, b, c], col | tex, uv }], clips: { name:
{ length, loop, channels: [{ bone, prop, keys: [[t, v, interp, in, out]] }],
events: [[t, name]] } }, collider, capsules }`. Large arrays are packed as
base64 (ADAM's `_z` convention), and the pack stores the same structure.

---

## D. Shared editor foundation (needed first)
All three tools sit on one editor shell:
* **An immediate-mode UI kit:**
  * buttons, sliders, dropdowns, text fields, lists, trees, tabs, splitters,
    scroll areas, colour (Pepto) pickers;
  * hover help on every control.

  Taken from ADAM's `scr_ui_widgets` pattern, plus PiX3LL3D's menu bar and
  shortcuts panel.
* **Pages:** Levels, Enemies, Creatures, Textures, Music, Sound, Game. Each page
  gets its own undo history and remembers its selection.
* **Viewport widgets:** orbit / fly camera, grid, gizmos (move / rotate / scale
  arrows), and picking (ray against sector polygons, mesh triangles and bones).
* **The project:** a `.ntc64proj` folder (`project.json` plus `levels/`,
  `creatures/`, `textures/`, `songs/`, `sfx/`), autosave, recent files.
