/// scr_menu
/// The Options menu: a MENU button in the corner (or Esc) opens an overlay over
/// the paused game with three tabs:
///   GAME     resume, restart level, Editor (Editor build only), quit
///   DISPLAY  fullscreen, window size, Pepto dither, debug views
///   CRT      on / off, scanlines off / progressive / interlaced, blur, curvature ...
/// Engine core: the Player has it too (without the Editor button and debug views).
/// The panel can be dragged by its title bar and made see-through (opacity 0.5,
/// no dimming of the game; off by default) so picture settings can be tuned while
/// watching the game. Both are remembered in settings.ini.
/// State on obj_engine (Create): menu_open, menu_tab, menu_crt_defs, menu_x,
/// menu_y (-1 = centred), menu_drag, menu_dx, menu_dy, menu_seethrough.

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
    menu_drag = false;
    ui_active = "";
    window_set_cursor(cr_default);
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

    var _s = ui_s;
    var _gw = display_get_gui_width();
    var _gh = display_get_gui_height();
    // Tallest tab (CRT): title, tabs, toggle, scanlines, 11 sliders, footer
    var _pw = 380 * _s;
    var _ph = 8 * _s + (ui_row + 4 * _s) * 2 + (ui_row + 3 * _s) * 2 + ui_row * 11 + ui_row + 16 * _s;
    var _bar = ui_row + 6 * _s;     // title bar: drag handle

    // --- Position: centred until dragged, always kept on screen ---
    if (menu_x < 0 || menu_y < 0)
    {
        menu_x = floor((_gw - _pw) / 2);
        menu_y = floor((_gh - _ph) / 2);
    }
    var _stw = (string_width("See-through") + 2 * UI_PAD) * _s + (ui_row - 4 * _s);
    var _st_x = menu_x + _pw - 8 * _s - _stw;
    var _st_y = menu_y + 3 * _s;
    var _on_bar = ui_hover(menu_x, menu_y, menu_x + _pw, menu_y + _bar);
    var _on_st = ui_hover(_st_x, _st_y, _st_x + _stw, _st_y + ui_row);
    if (_on_bar && !_on_st && ui_pressed && !ui_used)
    {
        menu_drag = true;
        menu_dx = ui_mx - menu_x;
        menu_dy = ui_my - menu_y;
        ui_used = true;
    }
    if (menu_drag)
    {
        if (ui_down)
        {
            menu_x = ui_mx - menu_dx;
            menu_y = ui_my - menu_dy;
        }
        else
        {
            menu_drag = false;
            settings_dirty = true;
        }
    }
    menu_x = clamp(menu_x, 0, max(0, _gw - _pw));
    menu_y = clamp(menu_y, 0, max(0, _gh - _ph));
    if (_on_bar || menu_drag)
    {
        window_set_cursor(cr_size_all);
    }
    else
    {
        window_set_cursor(cr_default);
    }

    // Dim the paused game behind the menu - unless it is see-through, so the
    // CRT / dither changes can be watched while they are made
    if (!menu_seethrough)
    {
        draw_set_alpha(0.55);
        ui_rect(0, 0, _gw, _gh, _c.dark, false);
    }
    var _alpha = 1;
    if (menu_seethrough)
    {
        _alpha = 0.5;
    }
    draw_set_alpha(_alpha);

    var _x1 = menu_x;
    var _y1 = menu_y;
    ui_panel(_x1, _y1, _x1 + _pw, _y1 + _ph);
    ui_rect(_x1, _y1, _x1 + _pw, _y1 + _bar, _c.edge, false);

    var _x = _x1 + 10 * _s;
    var _w = _pw - 20 * _s;
    var _y = _y1 + 4 * _s;
    ui_text(_x, _y, "OPTIONS  " + build_program_name() + " " + NTC64_VERSION, _c.panel);
    var _see = ui_toggle_on_bar(_st_x, _st_y, _stw, "See-through", menu_seethrough);
    if (_see != menu_seethrough)
    {
        menu_seethrough = _see;
        settings_dirty = true;
    }
    _y = _y1 + _bar + 6 * _s;

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

        var _dm = ui_stepper(_x, _y, _w, "Dither (F4)", menu_dither_names, dither_mode, true);
        if (_dm != dither_mode)
        {
            dither_mode = _dm;
            settings_dirty = true;
        }
        _y += _row;
        var _d = ui_slider("dither", _x, _y, _w, "Dither amount", dither, 0, 1, 0);
        if (_d != dither)
        {
            dither = _d;
            settings_dirty = true;
        }
        _y += _row;
        if (dither_mode >= DITHER_ED_FIRST && !fx_ok)
        {
            ui_text(_x, _y + 2 * _s, "(ntc64fx.dll missing: shown as Bayer 4x4)", _c.text);
        }
        _y += _row;

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

    ui_text(_x, _y1 + _ph - ui_row, "Esc: back to game. Drag the bar to move.", _c.text);
    draw_set_alpha(1);
}
