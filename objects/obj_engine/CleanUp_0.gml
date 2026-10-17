/// obj_engine - Clean Up

if (mouse_captured)
{
    window_mouse_set_locked(false);
}
if (settings_dirty)
{
    settings_save();
}
world_free(world);
tex_free_all();
render_free();
audio_free();
vertex_format_delete(global.WORLD_VFORMAT);
