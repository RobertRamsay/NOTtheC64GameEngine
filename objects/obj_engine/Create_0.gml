/// obj_engine - Create. Every instance variable is initialised here.

// --- Palette and textures ---
pepto_init();
pepto_u_array = pepto_uniform_array();
tex_init();
tex_make_test_set();

// --- World ---
world_init();
// Dev tool: build.ps1 -SaveLevel writes the built-in test level as JSON and quits
save_level_path = environment_get_variable("NTC64_SAVE_LEVEL");
if (save_level_path != "")
{
    level_save(world_test_level(), save_level_path);
}
level = level_load(working_directory + "levels/test.json");
if (is_undefined(level))
{
    level = world_test_level();
}
world = world_bake(level);

// --- Player ---
pl_x = 0;
pl_y = 0;
pl_z = 0;
pl_vz = 0;
pl_view_z = 0;
pl_yaw = 0;
pl_pitch = 0;
pl_sector = -1;
pl_floorz = 0;
pl_ceilz = 0;
pl_on_ground = true;
pl_noclip = false;
mouse_captured = false;
pawn_spawn(world);

// --- Rendering ---
rt_world = -1;
rt_locked = -1;
cam = camera_create();
rw_u = {};
lock_u = {};
render_uniforms();
lock_on = true;
dither = 1.0;
show_debug = true;
show_swatches = false;
frame_no = 0;

// --- Post FX ---
fx = postfx_defaults();
fx_u = postfx_uniforms();
fx_crt_on = true;

// The game image never goes through application_surface; keep it tiny.
application_surface_draw_enable(false);
surface_resize(application_surface, RENDER_W, RENDER_H);
gui_w = window_get_width();
gui_h = window_get_height();
display_set_gui_size(gui_w, gui_h);

// --- Self-test ---
shot_path = "";
shot_frame = AUTOSHOT_FRAME;
shot_use = -1;
shot_walk = [];
shot_walk_i = 0;
shot_walk_left = 0;
autoshot_setup();

window_set_caption("NOTtheC64GameEngine " + build_program_name() + " " + NTC64_VERSION);
show_debug_message("NOTtheC64GameEngine " + build_program_name() + ": level " + level.name + ", " + string(world.nsec) + " sectors, "
    + string(array_length(level.edges)) + " edges, " + string(world.tris) + " tris in " + string(world.nbatches) + " batches ("
    + string(array_length(world.groups)) + " groups, " + string(array_length(world.planes)) + " moving planes)");

if (save_level_path != "")
{
    game_end();
}
