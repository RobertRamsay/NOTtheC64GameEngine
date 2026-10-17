/// scr_ui
/// A small immediate-mode UI kit, drawn in Draw GUI (ADAM's scr_ui_widgets
/// pattern): every widget draws itself and returns what the user did this frame.
/// Engine core: the Player's Options menu uses it, and the Editor will grow on it.
/// The UI is not part of the game image and is not palette locked, but it uses
/// Pepto colours anyway (C64 blue screen style).
///
/// Sizes are in "UI pixels" scaled by ui_s (ui_scale()) so text stays readable
/// at any window size. State on obj_engine (Create): ui_s, ui_mx, ui_my,
/// ui_pressed, ui_down, ui_active, ui_used, ui_row.

#macro UI_PAD 4
/// Width of the label column of sliders / choices, in UI pixels
#macro UI_LABEL_W 136
#macro UI_VALUE_W 40

function ui_colours()
{
    return {
        panel: pepto_colour(PEPTO_BLUE),
        edge: pepto_colour(PEPTO_LIGHT_BLUE),
        text: pepto_colour(PEPTO_LIGHT_BLUE),
        bright: pepto_colour(PEPTO_WHITE),
        hot: pepto_colour(PEPTO_CYAN),
        fill: pepto_colour(PEPTO_LIGHT_BLUE),
        dim: pepto_colour(PEPTO_DARK_GREY),
        dark: pepto_colour(PEPTO_BLACK)
    };
}

/// @desc UI scale for the current window: 1 up to 1199 px high, 2 to 1799, ...
function ui_scale()
{
    return max(1, floor(display_get_gui_height() / 600));
}

/// @desc Height of one widget row at scale _s: the font plus a little air.
function ui_row_height(_s)
{
    draw_set_font(-1);
    return (string_height("M") + 4) * _s;
}

/// @desc Call once at the top of Draw GUI.
function ui_frame_begin()
{
    ui_s = ui_scale();
    ui_row = ui_row_height(ui_s);
    ui_mx = device_mouse_x_to_gui(0);
    ui_my = device_mouse_y_to_gui(0);
    ui_pressed = mouse_check_button_pressed(mb_left);
    ui_down = mouse_check_button(mb_left);
    ui_used = false;
    if (!ui_down)
    {
        ui_active = "";
    }
    draw_set_font(-1);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
    gpu_set_tex_filter(false);
}

function ui_hover(_x1, _y1, _x2, _y2)
{
    return (ui_mx >= _x1 && ui_mx < _x2 && ui_my >= _y1 && ui_my < _y2);
}

/// @desc A press inside the rect, not already taken by another widget.
function ui_click(_x1, _y1, _x2, _y2)
{
    if (ui_pressed && !ui_used && ui_hover(_x1, _y1, _x2, _y2))
    {
        ui_used = true;
        return true;
    }
    return false;
}

function ui_text(_x, _y, _str, _col)
{
    draw_set_colour(_col);
    draw_text_transformed(_x, _y, _str, ui_s, ui_s, 0);
}

function ui_text_w(_str)
{
    return string_width(_str) * ui_s;
}

function ui_rect(_x1, _y1, _x2, _y2, _col, _outline)
{
    draw_set_colour(_col);
    draw_rectangle(_x1, _y1, _x2 - 1, _y2 - 1, _outline);
}

/// @desc Panel with a border, C64 style.
function ui_panel(_x1, _y1, _x2, _y2)
{
    var _c = ui_colours();
    var _b = 2 * ui_s;
    ui_rect(_x1 - _b, _y1 - _b, _x2 + _b, _y2 + _b, _c.edge, false);
    ui_rect(_x1, _y1, _x2, _y2, _c.panel, false);
}

/// @desc Button. Returns true on the frame it is clicked.
function ui_button(_x, _y, _w, _label, _enabled)
{
    var _c = ui_colours();
    var _h = ui_row;
    var _hot = _enabled && ui_hover(_x, _y, _x + _w, _y + _h);
    if (!_enabled)
    {
        ui_rect(_x, _y, _x + _w, _y + _h, _c.dim, true);
        ui_text(_x + UI_PAD * ui_s, _y + 2 * ui_s, _label, _c.dim);
        return false;
    }
    if (_hot)
    {
        ui_rect(_x, _y, _x + _w, _y + _h, _c.hot, false);
        ui_text(_x + UI_PAD * ui_s, _y + 2 * ui_s, _label, _c.panel);
    }
    else
    {
        ui_rect(_x, _y, _x + _w, _y + _h, _c.fill, true);
        ui_text(_x + UI_PAD * ui_s, _y + 2 * ui_s, _label, _c.text);
    }
    return ui_click(_x, _y, _x + _w, _y + _h);
}

/// @desc On / off box. Returns the new value.
function ui_toggle(_x, _y, _w, _label, _val)
{
    var _c = ui_colours();
    var _h = ui_row;
    var _box = ui_row - 4 * ui_s;
    var _hot = ui_hover(_x, _y, _x + _w, _y + _h);
    var _col = _c.text;
    if (_hot)
    {
        _col = _c.hot;
    }
    ui_rect(_x, _y + 2 * ui_s, _x + _box, _y + 2 * ui_s + _box, _col, true);
    if (_val)
    {
        ui_rect(_x + 2 * ui_s, _y + 4 * ui_s, _x + _box - 2 * ui_s, _y + _box, _c.bright, false);
    }
    ui_text(_x + _box + UI_PAD * ui_s, _y + 2 * ui_s, _label, _col);
    if (ui_click(_x, _y, _x + _w, _y + _h))
    {
        return !_val;
    }
    return _val;
}

/// @desc A row of exclusive options. Returns the new index.
function ui_choice(_x, _y, _w, _label, _opts, _idx, _enabled)
{
    var _c = ui_colours();
    var _h = ui_row;
    var _lw = 0;
    if (_label != "")
    {
        _lw = UI_LABEL_W * ui_s;
        var _lc = _c.text;
        if (!_enabled)
        {
            _lc = _c.dim;
        }
        ui_text(_x, _y + 2 * ui_s, _label, _lc);
    }
    var _n = array_length(_opts);
    var _bw = (_w - _lw) / _n;
    var _out = _idx;
    for (var _i = 0; _i < _n; _i++)
    {
        var _bx = _x + _lw + _i * _bw;
        var _bx2 = _bx + _bw - ui_s;
        var _hot = _enabled && ui_hover(_bx, _y, _bx2, _y + _h);
        if (!_enabled)
        {
            ui_rect(_bx, _y, _bx2, _y + _h, _c.dim, true);
            ui_text(_bx + UI_PAD * ui_s, _y + 2 * ui_s, _opts[_i], _c.dim);
            continue;
        }
        if (_i == _idx)
        {
            ui_rect(_bx, _y, _bx2, _y + _h, _c.fill, false);
            ui_text(_bx + UI_PAD * ui_s, _y + 2 * ui_s, _opts[_i], _c.panel);
        }
        else
        {
            var _col = _c.text;
            if (_hot)
            {
                _col = _c.hot;
            }
            ui_rect(_bx, _y, _bx2, _y + _h, _col, true);
            ui_text(_bx + UI_PAD * ui_s, _y + 2 * ui_s, _opts[_i], _col);
        }
        if (_enabled && ui_click(_bx, _y, _bx2, _y + _h))
        {
            _out = _i;
        }
    }
    return _out;
}

/// @desc Slider with a label on the left and the value on the right.
/// _id must be unique per slider (it holds the drag). Returns the new value.
function ui_slider(_id, _x, _y, _w, _label, _val, _lo, _hi, _step)
{
    var _c = ui_colours();
    var _h = ui_row;
    var _lw = UI_LABEL_W * ui_s;
    var _vw = UI_VALUE_W * ui_s;
    var _tx0 = _x + _lw;
    var _tx1 = _x + _w - _vw - 6 * ui_s;
    var _th = 6 * ui_s;
    var _ty = _y + floor((_h - _th) / 2);

    var _hot = ui_hover(_tx0 - 4 * ui_s, _y, _tx1 + 4 * ui_s, _y + _h);
    if (_hot && ui_click(_tx0 - 4 * ui_s, _y, _tx1 + 4 * ui_s, _y + _h))
    {
        ui_active = _id;
    }
    if (ui_active == _id && ui_down)
    {
        var _t = clamp((ui_mx - _tx0) / max(_tx1 - _tx0, 1), 0, 1);
        _val = _lo + _t * (_hi - _lo);
        if (_step > 0)
        {
            _val = round(_val / _step) * _step;
        }
        _val = clamp(_val, _lo, _hi);
    }

    var _col = _c.text;
    if (_hot || ui_active == _id)
    {
        _col = _c.hot;
    }
    ui_text(_x, _y + 2 * ui_s, _label, _col);
    ui_rect(_tx0, _ty, _tx1, _ty + _th, _col, true);
    var _f = clamp((_val - _lo) / max(_hi - _lo, 0.0001), 0, 1);
    var _kx = _tx0 + _f * (_tx1 - _tx0);
    ui_rect(_tx0, _ty, max(_tx0 + 1, _kx), _ty + _th, _c.fill, false);
    ui_rect(_kx - ui_s, _ty - 2 * ui_s, _kx + 2 * ui_s, _ty + _th + 2 * ui_s, _c.bright, false);

    var _txt = string_format(_val, 1, 2);
    if (_step >= 1)
    {
        _txt = string(round(_val));
    }
    draw_set_halign(fa_right);
    ui_text(_x + _w, _y + 2 * ui_s, _txt, _c.bright);
    draw_set_halign(fa_left);
    return _val;
}

/// @desc Tab strip. Returns the new tab index.
function ui_tabs(_x, _y, _w, _names, _idx)
{
    return ui_choice(_x, _y, _w, "", _names, _idx, true);
}
