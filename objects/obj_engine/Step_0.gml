/// obj_engine - Step

frame_no += 1;

// Keep the GUI layer the size of the window
if (window_get_width() != gui_w || window_get_height() != gui_h)
{
    gui_w = max(window_get_width(), 1);
    gui_h = max(window_get_height(), 1);
    display_set_gui_size(gui_w, gui_h);
}

// --- Toggles ---
if (keyboard_check_pressed(vk_f1))
{
    if (show_debug)
    {
        show_debug = false;
    }
    else
    {
        show_debug = true;
    }
}
if (keyboard_check_pressed(vk_f2))
{
    if (show_swatches)
    {
        show_swatches = false;
    }
    else
    {
        show_swatches = true;
    }
}
if (keyboard_check_pressed(vk_f5))
{
    if (dither > 0)
    {
        dither = 0;
    }
    else
    {
        dither = 1;
    }
}
if (keyboard_check_pressed(vk_f6))
{
    if (fx_crt_on)
    {
        fx_crt_on = false;
    }
    else
    {
        fx_crt_on = true;
    }
}
if (keyboard_check_pressed(vk_f7))
{
    if (lock_on)
    {
        lock_on = false;
    }
    else
    {
        lock_on = true;
    }
}

if (keyboard_check_pressed(vk_f9))
{
    // debug hook: dual-SID + PCM test (scr_audio)
    audio_test_toggle();
}

if (shot_path == "")
{
    pawn_update(level);
}
audio_stream_step();
