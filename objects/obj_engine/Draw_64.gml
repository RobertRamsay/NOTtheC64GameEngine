/// obj_engine - Draw GUI. Present the locked game image, then debug text
/// (debug / editor text is not part of the game image and is not palette locked).

render_present();

if (show_debug)
{
    var _sec = "none";
    if (pl_sector >= 0)
    {
        _sec = string(pl_sector);
    }
    var _lock = "ON";
    if (!lock_on)
    {
        _lock = "OFF (debug)";
    }
    var _dith = "on";
    if (dither <= 0)
    {
        _dith = "off";
    }
    var _crt = "on";
    if (!fx_crt_on)
    {
        _crt = "off";
    }
    var _nc = "";
    if (pl_noclip)
    {
        _nc = "  NOCLIP";
    }

    var _lines = [
        "NOTtheC64GameEngine  " + string(RENDER_W) + "x" + string(RENDER_H) + "  " + string(fps) + " fps (" + string(round(fps_real)) + " uncapped)",
        "pos " + string(round(pl_x)) + ", " + string(round(pl_y)) + ", " + string(round(pl_z)) + "  yaw " + string(round(pl_yaw)) + "  pitch " + string(round(pl_pitch)) + "  sector " + _sec + _nc,
        "tris " + string(world_baked.tris) + "  batches " + string(array_length(world_baked.batches)),
        "F5 dither " + _dith + "   F6 CRT " + _crt + "   F7 Pepto lock " + _lock + "   N noclip   F1 hide",
        "Click to capture mouse, Tab/Esc to release. WASD + Shift, Space/C fly in noclip."
    ];

    draw_set_font(-1);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    for (var _i = 0; _i < array_length(_lines); _i++)
    {
        draw_set_colour(c_black);
        draw_text(9, 9 + _i * 16, _lines[_i]);
        draw_set_colour(pepto_colour(PEPTO_LIGHT_GREEN));
        draw_text(8, 8 + _i * 16, _lines[_i]);
    }
    draw_set_colour(c_white);
}
