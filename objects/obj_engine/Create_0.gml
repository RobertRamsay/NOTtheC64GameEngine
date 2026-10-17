/// obj_engine - Create. Every instance variable is initialised here.

// --- Palette and textures ---
pepto_init();
pepto_u_array = pepto_uniform_array();
tex_init();
tex_make_test_set();

// --- World ---
world_init();
level = world_test_level();
world_baked = world_bake(level);

// --- Player ---
pl_x = 0;
pl_y = 0;
pl_z = 0;
pl_vz = 0;
pl_view_z = 0;
pl_yaw = 0;
pl_pitch = 0;
pl_sector = -1;
pl_noclip = false;
mouse_captured = false;
pawn_spawn(level);

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

// --- Audio (scr_audio) ---
aud_ok = false;
aud_stereo = true;
aud_model_a = 0;          // chip A (left): 0 = 6581, 1 = 8580
aud_model_b = 1;          // chip B (right)
aud_engine = 0;           // 0 = reSID, 1 = reSID-fp
aud_gain = 1.0;
aud_cap = 0;
aud_log_a = -1;
aud_log_b = -1;
aud_queue = -1;
aud_inst = -1;
aud_playing = false;
aud_bufs = [];
aud_dead = [];
aud_src = -1;
aud_src_done = false;
aud_frames_queued = 0;
aud_t0 = 0;
aud_played = 0;
aud_test_pcm = -1;
audio_init();

// --- Self-test ---
shot_path = "";
autoshot_setup();
if (shot_path != "")
{
    // exercise the live stream too; autoshot_tick reports it and renders the test offline
    audio_test_toggle();
}

window_set_caption("NOTtheC64GameEngine " + build_program_name() + " " + NTC64_VERSION);
show_debug_message("NOTtheC64GameEngine " + build_program_name() + ": " + string(array_length(level.sectors)) + " sectors, "
    + string(world_baked.tris) + " tris in " + string(array_length(world_baked.batches)) + " batches");
