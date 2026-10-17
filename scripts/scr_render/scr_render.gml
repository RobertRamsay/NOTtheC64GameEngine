/// scr_render
/// The frame pipeline (see docs/ENGINE_DESIGN.md §2):
///   Draw:     rt_world  <- 3D world (sh_world), then 2D game overlays
///             rt_locked <- rt_world through sh_pepto_lock (every pixel Pepto)
///   Draw GUI: rt_locked -> window, letterboxed, through sh_crt when it is on
///
/// State on obj_engine (Create): rt_world, rt_locked, cam, rw_u, lock_u,
/// lock_on, dither, pepto_u_array, shot_path, shot_frame, shot_use, frame_no.

#macro RENDER_W 320
#macro RENDER_H 200
#macro RENDER_FOV 90
#macro RENDER_ZNEAR 2
#macro RENDER_ZFAR 16000

/// Distance at which diminishing light reaches its darkest (world units).
#macro RENDER_FALLOFF 1400

/// Frames to wait before the auto-screenshot self-test fires.
#macro AUTOSHOT_FRAME 30

function render_uniforms()
{
    rw_u = {
        falloff: shader_get_uniform(sh_world, "u_falloff")
    };
    lock_u = {
        pal: shader_get_uniform(sh_pepto_lock, "u_pal"),
        dither: shader_get_uniform(sh_pepto_lock, "u_dither"),
        on: shader_get_uniform(sh_pepto_lock, "u_on")
    };
}

function render_ensure_surfaces()
{
    if (!surface_exists(rt_world))
    {
        surface_depth_disable(false);
        rt_world = surface_create(RENDER_W, RENDER_H);
    }
    if (!surface_exists(rt_locked))
    {
        surface_depth_disable(true);
        rt_locked = surface_create(RENDER_W, RENDER_H);
        surface_depth_disable(false);
    }
}

/// @desc Draw the 3D world into rt_world. Call in the Draw event.
function render_world(_w)
{
    render_ensure_surfaces();

    surface_set_target(rt_world);
    draw_clear_alpha(c_black, 1);

    camera_set_view_mat(cam, pawn_view_matrix());
    // RENDER_FOV is horizontal (Doom's 90); GameMaker wants vertical. Negative
    // FOV and aspect are GameMaker's usual fix-up for a +Z-up camera.
    var _vfov = 2 * darctan(dtan(RENDER_FOV / 2) * RENDER_H / RENDER_W);
    camera_set_proj_mat(cam, matrix_build_projection_perspective_fov(-_vfov, -RENDER_W / RENDER_H, RENDER_ZNEAR, RENDER_ZFAR));
    camera_apply(cam);

    gpu_set_ztestenable(true);
    gpu_set_zwriteenable(true);
    gpu_set_cullmode(cull_noculling);
    gpu_set_texrepeat(true);
    gpu_set_tex_filter(false);
    gpu_set_alphatestenable(true);
    gpu_set_alphatestref(128);

    shader_set(sh_world);
    shader_set_uniform_f(rw_u.falloff, _w.falloff);
    vis_update(_w, pl_x, pl_y, pl_view_z, pl_yaw, pl_pitch, pl_z);
    world_draw(_w);
    shader_reset();

    gpu_set_alphatestenable(false);
    gpu_set_texrepeat(false);
    gpu_set_ztestenable(false);
    gpu_set_zwriteenable(false);

    surface_reset_target();
}

/// @desc Debug strip along the bottom of rt_world (F2): the 16 Pepto colours as
/// plain rectangles, then every texture. After the lock the swatches must look
/// exactly the same - if one changes, the lock or the colour order is wrong.
function render_swatches()
{
    surface_set_target(rt_world);
    var _y0 = RENDER_H - 20;
    for (var _i = 0; _i < PEPTO_COUNT; _i++)
    {
        draw_set_colour(pepto_colour(_i));
        draw_rectangle(_i * 8, _y0, _i * 8 + 7, _y0 + 3, false);
    }
    draw_set_colour(c_white);
    for (var _i = 0; _i < array_length(global.TEX_NAMES); _i++)
    {
        var _t = tex_get(global.TEX_NAMES[_i]);
        draw_sprite(_t.spr, 0, _i * 17, _y0 + 4);
    }
    surface_reset_target();
}

/// @desc rt_world -> rt_locked through the Pepto lock. Call after every game
/// overlay has been drawn into rt_world.
function render_lock()
{
    render_ensure_surfaces();

    surface_set_target(rt_locked);
    draw_clear_alpha(c_black, 1);
    gpu_set_tex_filter(false);
    gpu_set_blendenable(false);
    shader_set(sh_pepto_lock);
    shader_set_uniform_f_array(lock_u.pal, pepto_u_array);
    shader_set_uniform_f(lock_u.dither, dither);
    if (lock_on)
    {
        shader_set_uniform_f(lock_u.on, 1);
    }
    else
    {
        shader_set_uniform_f(lock_u.on, 0);
    }
    draw_surface(rt_world, 0, 0);
    shader_reset();
    gpu_set_blendenable(true);
    surface_reset_target();
}

/// @desc Letterboxed placement of the game image in the window: [x, y, w, h].
function render_screen_rect()
{
    var _gw = display_get_gui_width();
    var _gh = display_get_gui_height();
    var _s = min(_gw / RENDER_W, _gh / RENDER_H);
    if (!fx_crt_on && _s >= 1)
    {
        // Without the CRT, keep pixels square and even
        _s = floor(_s);
    }
    var _w = RENDER_W * _s;
    var _h = RENDER_H * _s;
    return [floor((_gw - _w) / 2), floor((_gh - _h) / 2), _w, _h];
}

/// @desc Put the game image on screen. Call first in Draw GUI.
function render_present()
{
    draw_clear(c_black);
    if (!surface_exists(rt_locked))
    {
        return;
    }
    var _r = render_screen_rect();
    postfx_present(rt_locked, _r[0], _r[1], _r[2], _r[3]);
}

function render_free()
{
    if (surface_exists(rt_world))
    {
        surface_free(rt_world);
    }
    if (surface_exists(rt_locked))
    {
        surface_free(rt_locked);
    }
    rt_world = -1;
    rt_locked = -1;
    camera_destroy(cam);
}

// ============================================================
//  AUTO-SCREENSHOT SELF-TEST
// ============================================================

/// @desc Read NTC64_AUTOSHOT (png path) and NTC64_AUTOSHOT_POSE ("x,y,z,yaw,pitch").
function autoshot_setup()
{
    shot_path = environment_get_variable("NTC64_AUTOSHOT");
    if (shot_path == "")
    {
        return;
    }
    var _pose = environment_get_variable("NTC64_AUTOSHOT_POSE");
    if (_pose != "")
    {
        var _p = string_split(_pose, ",");
        if (array_length(_p) >= 5)
        {
            pl_x = real(_p[0]);
            pl_y = real(_p[1]);
            pl_z = real(_p[2]);
            pl_yaw = real(_p[3]);
            pl_pitch = real(_p[4]);
            pl_noclip = true;
            pl_view_z = pl_z + PL_EYE;
        }
    }
    // Walk script (build.ps1 -Walk): the pawn walks with collision, so no noclip
    var _walk = environment_get_variable("NTC64_AUTOSHOT_WALK");
    if (_walk != "")
    {
        shot_walk = string_split(_walk, ",", true);
        pl_noclip = false;
        pl_vz = 0;
    }
    if (environment_get_variable("NTC64_AUTOSHOT_SWATCHES") != "")
    {
        show_swatches = true;
    }
    // Optional: shoot at frame N instead of AUTOSHOT_FRAME, press use at frame 2
    var _frames = environment_get_variable("NTC64_AUTOSHOT_FRAMES");
    if (_frames != "")
    {
        shot_frame = max(3, real(_frames));
    }
    if (environment_get_variable("NTC64_AUTOSHOT_USE") != "")
    {
        shot_use = 2;
    }
    // Portal culling off (build.ps1 -NoVis): the same shot must come out identical
    if (environment_get_variable("NTC64_AUTOSHOT_NOVIS") != "")
    {
        world.vis_on = false;
    }
    show_debug_message("AUTOSHOT armed: " + shot_path);
}

/// @desc One Step of the self-test: the -Use press and the -Walk script.
/// Script commands (comma separated): f<n> / b<n> forward / back n frames,
/// l<n> / r<n> strafe, w<n> wait, t<deg> turn left, e use, s shoot, j jump,
/// p print "WALK x, y, z sector" to the log.
function autoshot_step()
{
    if (frame_no == shot_use)
    {
        pawn_use(world);
    }
    var _fwd = 0;
    var _side = 0;
    var _up = 0;
    while (shot_walk_i < array_length(shot_walk))
    {
        var _cmd = string_trim(shot_walk[shot_walk_i]);
        var _op = string_lower(string_char_at(_cmd, 1));
        var _arg = 0;
        if (string_length(_cmd) > 1)
        {
            _arg = real(string_delete(_cmd, 1, 1));
        }
        if (_op == "t" || _op == "e" || _op == "s" || _op == "p" || _op == "j")
        {
            // Instant commands
            if (_op == "j")
            {
                _up = 1;
            }
            else if (_op == "t")
            {
                pl_yaw = (pl_yaw + _arg + 360) mod 360;
            }
            else if (_op == "e")
            {
                pawn_use(world);
            }
            else if (_op == "s")
            {
                pawn_shoot(world);
            }
            else
            {
                show_debug_message("WALK frame " + string(frame_no) + ": " + string_format(pl_x, 0, 1) + ", " + string_format(pl_y, 0, 1) + ", "
                    + string_format(pl_z, 0, 1) + "  sector " + string(pl_sector) + "  " + world.last_event);
            }
            shot_walk_i += 1;
            continue;
        }
        if (shot_walk_left <= 0)
        {
            shot_walk_left = max(1, _arg);
        }
        if (_op == "f")
        {
            _fwd = 1;
        }
        else if (_op == "b")
        {
            _fwd = -1;
        }
        else if (_op == "l")
        {
            _side = 1;
        }
        else if (_op == "r")
        {
            _side = -1;
        }
        shot_walk_left -= 1;
        if (shot_walk_left <= 0)
        {
            shot_walk_i += 1;
        }
        break;
    }
    if (!pl_noclip)
    {
        pawn_walk(world, _fwd, _side, _up, PL_WALK);
    }
}

/// @desc Count pixels of rt_locked that are not exactly a Pepto colour.
function autoshot_count_bad()
{
    var _n = RENDER_W * RENDER_H;
    var _buf = buffer_create(_n * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, rt_locked, 0);
    var _bad = 0;
    var _first = "";
    for (var _i = 0; _i < _n; _i++)
    {
        var _r = buffer_peek(_buf, _i * 4, buffer_u8);
        var _g = buffer_peek(_buf, _i * 4 + 1, buffer_u8);
        var _b = buffer_peek(_buf, _i * 4 + 2, buffer_u8);
        if (!pepto_is_exact(_r, _g, _b))
        {
            if (_bad == 0)
            {
                _first = string(_r) + "," + string(_g) + "," + string(_b) + " at " + string(_i mod RENDER_W) + "," + string(_i div RENDER_W);
            }
            _bad += 1;
        }
    }
    buffer_delete(_buf);
    if (_bad > 0)
    {
        show_debug_message("AUTOSHOT first bad pixel " + _first);
    }
    return _bad;
}

/// @desc Call at the end of Draw (after render_lock): save, verify, quit.
function autoshot_tick()
{
    if (shot_path == "" || frame_no != shot_frame)
    {
        return;
    }
    surface_save(rt_locked, shot_path);
    surface_save(rt_world, shot_path + "_raw.png");
    var _bad = autoshot_count_bad();
    if (_bad == 0)
    {
        show_debug_message("AUTOSHOT " + shot_path + " ok - every pixel is Pepto (" + string(world.tris) + " tris, " + string(world.drawn) + " of " + string(world.nbatches) + " batches drawn, " + string(world.vis_count) + " of " + string(world.nsec) + " sectors visible)");
    }
    else
    {
        show_debug_message("AUTOSHOT " + shot_path + " FAIL - " + string(_bad) + " pixels are not Pepto");
    }
    audio_selftest(shot_path + "_audio.wav");
    game_end();
}
