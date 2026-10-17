/// scr_menu
/// The Options menu: a MENU button in the corner (or Esc) opens an overlay over
/// the paused game with three tabs:
///   GAME     resume, restart level, Editor (Editor build only), quit
///   DISPLAY  fullscreen, window size, Pepto dither, debug views
///   CRT      on / off, scanlines off / progressive / interlaced, blur, curvature ...
/// Engine core: the Player has it too (without the Editor button and debug views).
/// State on obj_engine (Create): menu_open, menu_tab, menu_crt_defs.

#macro MENU_TAB_GAME 0
#macro MENU_TAB_DISPLAY 1
#macro MENU_TAB_CRT 2

function menu_open_now()
{
    menu_open = true;
    if (mouse_captured)
    {
        mouse_captured = false;
        window_mouse_set_locked(false);
    }
}

function menu_close()
{
    menu_open = false;
    ui_active = "";
    if (settings_dirty)
    {
        settings_save();
    }
}

/// @desc The small MENU button shown in the top-right corner while playing.
function menu_button_rect()
{
    var _s = ui_scale();
    var _h = ui_row_height(_s);
    var _w = (string_width("MENU") + 2 * UI_PAD) * _s;
    var _x2 = display_get_gui_width() - 6 * _s;
    var _y1 = 6 * _s;
    return [_x2 - _w, _y1, _x2, _y1 + _h];
}

/// @desc Step: Esc and the corner button. Returns true while the game is paused.
function menu_step()
{
    if (keyboard_check_pressed(vk_escape))
    {
        if (menu_open)
        {
            menu_close();
        }
        else
        {
            menu_open_now();
        }
        return true;
    }
    if (!menu_open && !mouse_captured && mouse_check_button_pressed(mb_left))
    {
        var _r = menu_button_rect();
        var _mx = device_mouse_x_to_gui(0);
        var _my = device_mouse_y_to_gui(0);
        if (_mx >= _r[0] && _mx < _r[2] && _my >= _r[1] && _my < _r[3])
        {
            menu_open_now();
            return true;
        }
    }
    return menu_open;
}

function menu_restart_level()
{
    world_free(world);
    world = world_bake(level);
    pawn_spawn(world);
}

/// @desc Draw GUI: the corner button, or the whole menu when it is open.
function menu_draw()
{
    var _c = ui_colours();
    if (!menu_open)
    {
        if (!mouse_captured)
        {
            var _r = menu_button_rect();
            var _hot = ui_hover(_r[0], _r[1], _r[2], _r[3]);
            if (_hot)
            {
                ui_rect(_r[0], _r[1], _r[2], _r[3], _c.hot, false);
                ui_text(_r[0] + UI_PAD * ui_s, _r[1] + 2 * ui_s, "MENU", _c.panel);
            }
            else
            {
                ui_rect(_r[0], _r[1], _r[2], _r[3], _c.panel, false);
                ui_rect(_r[0], _r[1], _r[2], _r[3], _c.edge, true);
                ui_text(_r[0] + UI_PAD * ui_s, _r[1] + 2 * ui_s, "MENU", _c.text);
            }
        }
        return;
    }

    // Dim the paused game behind the menu
    draw_set_alpha(0.55);
    ui_rect(0, 0, display_get_gui_width(), display_get_gui_height(), _c.dark, false);
    draw_set_alpha(1);

    var _s = ui_s;
    // Tallest tab (CRT): title, tabs, toggle, scanlines, 11 sliders, footer
    var _pw = 380 * _s;
    var _ph = 8 * _s + (ui_row + 4 * _s) * 2 + (ui_row + 3 * _s) * 2 + ui_row * 11 + ui_row + 16 * _s;
    var _x1 = floor((display_get_gui_width() - _pw) / 2);
    var _y1 = floor((display_get_gui_height() - _ph) / 2);
    ui_panel(_x1, _y1, _x1 + _pw, _y1 + _ph);

    var _x = _x1 + 10 * _s;
    var _w = _pw - 20 * _s;
    var _y = _y1 + 8 * _s;
    ui_text(_x, _y, "NOTtheC64GameEngine " + build_program_name() + " " + NTC64_VERSION, _c.bright);
    _y += ui_row + 4 * _s;

    menu_tab = ui_tabs(_x, _y, _w, ["GAME", "DISPLAY", "CRT"], menu_tab);
    _y += ui_row + 4 * _s;
    var _row = ui_row + 3 * _s;

    if (menu_tab == MENU_TAB_GAME)
    {
        if (ui_button(_x, _y, _w, "Resume", true))
        {
            menu_close();
        }
        _y += _row + 2 * _s;
        if (ui_button(_x, _y, _w, "Restart level", true))
        {
            menu_restart_level();
            menu_close();
        }
        _y += _row + 2 * _s;
        if (NTC64_EDITOR)
        {
            // The Editor shell arrives with milestone 4 (docs/ENGINE_DESIGN.md §9)
            ui_button(_x, _y, _w, "Editor (milestone 4)", false);
            _y += _row + 2 * _s;
        }
        if (ui_button(_x, _y, _w, "Quit to desktop", true))
        {
            menu_close();
            game_end();
        }
    }
    else if (menu_tab == MENU_TAB_DISPLAY)
    {
        var _fs = ui_toggle(_x, _y, _w, "Fullscreen (F11)", set_fullscreen);
        if (_fs != set_fullscreen)
        {
            settings_toggle_fullscreen();
        }
        _y += _row;
        var _ws = ui_choice(_x, _y, _w, "Window size", ["x1", "x2", "x3", "x4", "x5", "x6"], set_win_scale - 1, !set_fullscreen);
        if (_ws != set_win_scale - 1)
        {
            set_win_scale = _ws + 1;
            settings_apply_window();
            settings_dirty = true;
        }
        _y += _row;
        ui_text(_x, _y + 2 * _s, "(or drag the window edges to any size)", _c.text);
        _y += _row + 4 * _s;

        var _d = ui_slider("dither", _x, _y, _w, "Pepto dither", dither, 0, 1, 0);
        if (_d != dither)
        {
            dither = _d;
            settings_dirty = true;
        }
        _y += _row + 4 * _s;

        show_debug = ui_toggle(_x, _y, _w, "Debug text (F1)", show_debug);
        _y += _row;
        if (NTC64_EDITOR)
        {
            show_swatches = ui_toggle(_x, _y, _w, "Palette strip (F2)", show_swatches);
            _y += _row;
            lock_on = ui_toggle(_x, _y, _w, "Pepto lock (F7, debug)", lock_on);
            _y += _row;
        }
    }
    else
    {
        var _on = ui_toggle(_x, _y, _w / 2, "CRT (F6)", fx_crt_on);
        if (_on != fx_crt_on)
        {
            fx_crt_on = _on;
            settings_dirty = true;
        }
        var _dw = (string_width("Defaults") + 2 * UI_PAD) * _s;
        if (ui_button(_x + _w - _dw, _y, _dw, "Defaults", true))
        {
            fx = postfx_defaults();
            settings_dirty = true;
        }
        _y += _row;
        var _sm = ui_choice(_x, _y, _w, "Scanlines", ["Off", "Prog.", "Interl."], fx.crt_scan_mode, fx_crt_on);
        if (_sm != fx.crt_scan_mode)
        {
            fx.crt_scan_mode = _sm;
            settings_dirty = true;
        }
        _y += _row + 2 * _s;
        for (var _i = 0; _i < array_length(menu_crt_defs); _i++)
        {
            var _sd = menu_crt_defs[_i];
            var _v = ui_slider(_sd.key, _x, _y, _w, _sd.label, fx[$ _sd.key], _sd.lo, _sd.hi, _sd.step);
            if (_v != fx[$ _sd.key])
            {
                fx[$ _sd.key] = _v;
                settings_dirty = true;
            }
            _y += ui_row;
        }
    }

    ui_text(_x, _y1 + _ph - ui_row, "Esc: back to the game", _c.text);
}
