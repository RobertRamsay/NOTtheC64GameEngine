/// obj_engine - Draw. The game image: world -> 2D overlays -> palette lock.

render_world(world);

// 2D game overlays - HUD, weapon, billboards - get drawn into rt_world here,
// before the lock, so they obey the palette too.
if (show_swatches)
{
    render_swatches();
}

render_lock();
autoshot_tick();
