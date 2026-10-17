/// scr_settings
/// Per-machine display settings (window, picture, CRT), kept in settings.ini in
/// the game's save folder. Engine core: the Player has its own copy per game.
/// State on obj_engine (Create): set_fullscreen, set_win_scale, settings_dirty,
/// plus dither, fx_crt_on and fx (scr_postfx).

#macro SETTINGS_FILE "settings.ini"
#macro WIN_SCALE_MAX 6

/// @desc Read settings.ini over the defaults already in place.
function settings_load()
{
    ini_open(SETTINGS_FILE);
    set_fullscreen = ini_read_real("display", "fullscreen", set_fullscreen) != 0;
    set_win_scale = clamp(round(ini_read_real("display", "window_scale", set_win_scale)), 1, WIN_SCALE_MAX);
    dither = clamp(ini_read_real("picture", "dither", dither), 0, 1);
    fx_crt_on = ini_read_real("crt", "on", fx_crt_on) != 0;
    fx.crt_scan_mode = clamp(round(ini_read_real("crt", "scan_mode", fx.crt_scan_mode)), SCAN_OFF, SCAN_INTERLACED);
    var _defs = postfx_slider_defs();
    for (var _i = 0; _i < array_length(_defs); _i++)
    {
        var _d = _defs[_i];
        fx[$ _d.key] = clamp(ini_read_real("crt", _d.key, fx[$ _d.key]), _d.lo, _d.hi);
    }
    ini_close();
    settings_dirty = false;
}

function settings_save()
{
    ini_open(SETTINGS_FILE);
    ini_write_real("display", "fullscreen", set_fullscreen);
    ini_write_real("display", "window_scale", set_win_scale);
    ini_write_real("picture", "dither", dither);
    ini_write_real("crt", "on", fx_crt_on);
    ini_write_real("crt", "scan_mode", fx.crt_scan_mode);
    var _defs = postfx_slider_defs();
    for (var _i = 0; _i < array_length(_defs); _i++)
    {
        var _k = _defs[_i].key;
        ini_write_real("crt", _k, fx[$ _k]);
    }
    ini_close();
    settings_dirty = false;
}

/// @desc Put the window in the chosen mode: fullscreen, or windowed at
/// set_win_scale x the game image (320 x 200 -> 640 x 400, 960 x 600 ...).
/// The window stays freely resizable; the image is letterboxed into it.
function settings_apply_window()
{
    if (set_fullscreen)
    {
        window_set_fullscreen(true);
        return;
    }
    if (window_get_fullscreen())
    {
        window_set_fullscreen(false);
    }
    var _w = RENDER_W * set_win_scale;
    var _h = RENDER_H * set_win_scale;
    // Never bigger than the display
    while (set_win_scale > 1 && (_w > display_get_width() || _h > display_get_height() - 64))
    {
        set_win_scale -= 1;
        _w = RENDER_W * set_win_scale;
        _h = RENDER_H * set_win_scale;
    }
    window_set_size(_w, _h);
    call_later(1, time_source_units_frames, function()
    {
        window_center();
    });
}

function settings_toggle_fullscreen()
{
    if (set_fullscreen)
    {
        set_fullscreen = false;
    }
    else
    {
        set_fullscreen = true;
    }
    settings_apply_window();
    settings_save();
}
