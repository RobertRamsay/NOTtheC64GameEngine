/// scr_player
/// First-person camera and movement. Collision is sector based: a move is
/// allowed when every corner of the player's box lands in a sector whose floor
/// is at most PL_STEP above the feet and whose height leaves PL_HEAD of room.
/// (Proper radius-vs-edge collision with sliding comes with the world milestone.)
///
/// State lives on obj_engine (initialised in Create): pl_x, pl_y, pl_z (feet),
/// pl_vz, pl_view_z, pl_yaw, pl_pitch, pl_sector, pl_noclip, mouse_captured.

#macro PL_EYE    48
#macro PL_STEP   24
#macro PL_HEAD   56
#macro PL_RADIUS 12
#macro PL_WALK   4
#macro PL_RUN    8
#macro PL_GRAVITY 0.8
#macro PL_MOUSE_SENS 0.15

function player_spawn(_level)
{
    pl_x = _level.start.x;
    pl_y = _level.start.y;
    pl_yaw = _level.start.angle;
    pl_pitch = 0;
    pl_vz = 0;
    pl_sector = world_sector_at(_level, pl_x, pl_y);
    if (pl_sector >= 0)
    {
        pl_z = _level.sectors[pl_sector].floor;
    }
    else
    {
        pl_z = 0;
    }
    pl_view_z = pl_z + PL_EYE;
}

/// @desc Can the player's feet at height _feet stand at (_px, _py)?
function player_spot_ok(_level, _px, _py, _feet)
{
    var _corners = [-1, -1, 1, -1, 1, 1, -1, 1];
    for (var _i = 0; _i < 4; _i++)
    {
        var _cx = _px + _corners[_i * 2] * PL_RADIUS;
        var _cy = _py + _corners[_i * 2 + 1] * PL_RADIUS;
        var _s = world_sector_at(_level, _cx, _cy);
        if (_s < 0)
        {
            return false;
        }
        var _sec = _level.sectors[_s];
        if (_sec.floor - _feet > PL_STEP)
        {
            return false;
        }
        if (_sec.ceil - max(_sec.floor, _feet) < PL_HEAD)
        {
            return false;
        }
    }
    return true;
}

/// @desc Mouse capture, look and movement. Call once per Step.
function player_update(_level)
{
    // --- Mouse capture ---
    if (!mouse_captured && mouse_check_button_pressed(mb_left))
    {
        mouse_captured = true;
        window_mouse_set_locked(true);
    }
    if (mouse_captured && (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(vk_tab)))
    {
        mouse_captured = false;
        window_mouse_set_locked(false);
    }

    // --- Look ---
    if (mouse_captured)
    {
        pl_yaw -= window_mouse_get_delta_x() * PL_MOUSE_SENS;
        pl_pitch -= window_mouse_get_delta_y() * PL_MOUSE_SENS;
    }
    if (keyboard_check(vk_left))
    {
        pl_yaw += 3;
    }
    if (keyboard_check(vk_right))
    {
        pl_yaw -= 3;
    }
    if (keyboard_check(vk_pageup))
    {
        pl_pitch += 2;
    }
    if (keyboard_check(vk_pagedown))
    {
        pl_pitch -= 2;
    }
    pl_yaw = (pl_yaw + 360) mod 360;
    pl_pitch = clamp(pl_pitch, -85, 85);

    if (keyboard_check_pressed(ord("N")))
    {
        if (pl_noclip)
        {
            pl_noclip = false;
            pl_vz = 0;
        }
        else
        {
            pl_noclip = true;
        }
    }

    // --- Move ---
    var _fwd = keyboard_check(ord("W")) - keyboard_check(ord("S"));
    if (keyboard_check(vk_up))
    {
        _fwd += 1;
    }
    if (keyboard_check(vk_down))
    {
        _fwd -= 1;
    }
    var _side = keyboard_check(ord("A")) - keyboard_check(ord("D"));
    var _speed = PL_WALK;
    if (keyboard_check(vk_shift))
    {
        _speed = PL_RUN;
    }

    var _dx = (dcos(pl_yaw) * _fwd + dcos(pl_yaw + 90) * _side) * _speed;
    var _dy = (-dsin(pl_yaw) * _fwd - dsin(pl_yaw + 90) * _side) * _speed;
    if (_fwd != 0 && _side != 0)
    {
        _dx *= 0.7071;
        _dy *= 0.7071;
    }

    if (pl_noclip)
    {
        pl_x += _dx;
        pl_y += _dy;
        pl_z += (keyboard_check(vk_space) - keyboard_check(ord("C"))) * _speed;
        pl_view_z = pl_z + PL_EYE;
        pl_sector = world_sector_at(_level, pl_x, pl_y);
        return;
    }

    // Axis by axis, so the player slides along walls
    if (player_spot_ok(_level, pl_x + _dx, pl_y, pl_z))
    {
        pl_x += _dx;
    }
    if (player_spot_ok(_level, pl_x, pl_y + _dy, pl_z))
    {
        pl_y += _dy;
    }

    // --- Floor, steps and falling ---
    pl_sector = world_sector_at(_level, pl_x, pl_y);
    var _floor = pl_z;
    if (pl_sector >= 0)
    {
        _floor = _level.sectors[pl_sector].floor;
    }

    if (pl_z < _floor)
    {
        // Step up; the eye eases up after it (below)
        pl_z = _floor;
        pl_vz = 0;
    }
    else if (pl_z > _floor)
    {
        pl_vz -= PL_GRAVITY;
        pl_z += pl_vz;
        if (pl_z <= _floor)
        {
            pl_z = _floor;
            pl_vz = 0;
        }
    }

    var _want = pl_z + PL_EYE;
    if (pl_view_z < _want)
    {
        pl_view_z = min(_want, pl_view_z + max(2, (_want - pl_view_z) * 0.35));
    }
    else
    {
        pl_view_z = _want;
    }
}

/// @desc View matrix for the player's eye (+Z up).
function player_view_matrix()
{
    var _lx = dcos(pl_yaw) * dcos(pl_pitch);
    var _ly = -dsin(pl_yaw) * dcos(pl_pitch);
    var _lz = dsin(pl_pitch);
    return matrix_build_lookat(pl_x, pl_y, pl_view_z, pl_x + _lx, pl_y + _ly, pl_view_z + _lz, 0, 0, 1);
}
