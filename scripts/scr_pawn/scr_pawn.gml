/// scr_pawn
/// First-person camera and movement. The pawn is a circle of PL_RADIUS in plan
/// and PL_HEAD tall. Collision is circle against edges: a one-sided edge (or one
/// flagged EDGE_BLOCK) always blocks; a two-sided edge blocks when its opening
/// is a step of more than PL_STEP up, leaves less than PL_HEAD of room, or would
/// hit the pawn's head. Blocked moves slide along the wall. Floor and ceiling
/// heights come from every sector the circle touches (Doom's floorz / ceilingz),
/// so the pawn stands on ledges and steps up stairs before its centre crosses.
///
/// State lives on obj_engine (initialised in Create): pl_x, pl_y, pl_z (feet),
/// pl_vz, pl_view_z, pl_yaw, pl_pitch, pl_sector, pl_noclip, pl_floorz,
/// pl_ceilz, pl_on_ground, mouse_captured.

#macro PL_EYE    48
#macro PL_STEP   24
#macro PL_HEAD   56
#macro PL_RADIUS 12
#macro PL_WALK   4
#macro PL_RUN    8
#macro PL_GRAVITY 0.8
#macro PL_MOUSE_SENS 0.15
/// Downward step that is followed instead of fallen (slopes, lifts going down).
#macro PL_STICK  8
/// Reach of the use key, from the pawn's centre (Doom's USERANGE).
#macro PL_USE_RANGE 64
#macro PL_SHOOT_RANGE 4096

function pawn_spawn(_w)
{
    var _lv = _w.level;
    pl_x = 0;
    pl_y = 0;
    pl_yaw = 0;
    for (var _i = 0; _i < array_length(_lv.things); _i++)
    {
        var _t = _lv.things[_i];
        if (_t.type == "player_start")
        {
            pl_x = _t.x;
            pl_y = _t.y;
            pl_yaw = _t.angle;
            break;
        }
    }
    pl_pitch = 0;
    pl_vz = 0;
    pl_sector = world_sector_at(_w, pl_x, pl_y, 100000);
    if (pl_sector >= 0)
    {
        pl_z = world_floor_at(_w, pl_sector, pl_x, pl_y);
    }
    else
    {
        pl_z = 0;
    }
    pl_floorz = pl_z;
    pl_ceilz = pl_z + PL_HEAD;
    pl_on_ground = true;
    pl_view_z = pl_z + PL_EYE;
}

/// @desc Does edge _e stop a pawn with its feet at _feet, touching it at (x, y)?
function pawn_edge_blocks(_w, _e, _cx, _cy, _feet)
{
    var _ed = _w.edges[_e];
    if (_ed.back < 0 || (_ed.flags & EDGE_BLOCK) != 0)
    {
        return true;
    }
    var _op = world_opening(_w, _e, _cx, _cy);
    if (_op[1] - _op[0] < PL_HEAD)
    {
        return true;
    }
    if (_op[1] - _feet < PL_HEAD)
    {
        return true;
    }
    if (_op[0] - _feet > PL_STEP)
    {
        return true;
    }
    return false;
}

/// @desc Push (_nx, _ny) out of every blocking edge, keeping it on the side
/// it came from (_ox, _oy). Returns [x, y, still_stuck].
function pawn_resolve(_w, _ox, _oy, _nx, _ny)
{
    var _r = PL_RADIUS;
    var _stuck = false;
    for (var _it = 0; _it < 4; _it++)
    {
        var _near = world_edges_near(_w, _nx - _r, _ny - _r, _nx + _r, _ny + _r);
        var _pushed = false;
        _stuck = false;
        for (var _i = 0; _i < array_length(_near); _i++)
        {
            var _e = _near[_i];
            var _ed = _w.edges[_e];
            var _a = _w.verts[_ed.v0];
            var _b = _w.verts[_ed.v1];
            var _dx = _b[0] - _a[0];
            var _dy = _b[1] - _a[1];
            var _l2 = max(_dx * _dx + _dy * _dy, 0.0001);
            var _t = clamp(((_nx - _a[0]) * _dx + (_ny - _a[1]) * _dy) / _l2, 0, 1);
            var _cx = _a[0] + _dx * _t;
            var _cy = _a[1] + _dy * _t;
            var _d = point_distance(_nx, _ny, _cx, _cy);
            if (_d >= _r - 0.001)
            {
                continue;
            }
            if (!pawn_edge_blocks(_w, _e, _cx, _cy, pl_z))
            {
                continue;
            }
            var _px = 0;
            var _py = 0;
            if (_t > 0 && _t < 1)
            {
                // Against the middle of the edge: out along its normal, to the side we came from
                var _len = sqrt(_l2);
                _px = -_dy / _len;
                _py = _dx / _len;
                if ((_ox - _cx) * _px + (_oy - _cy) * _py < 0)
                {
                    _px = -_px;
                    _py = -_py;
                }
            }
            else if (_d > 0.0001)
            {
                // Against a corner: straight out from it
                _px = (_nx - _cx) / _d;
                _py = (_ny - _cy) / _d;
            }
            else
            {
                _px = _ox - _cx;
                _py = _oy - _cy;
                var _pl = max(point_distance(0, 0, _px, _py), 0.0001);
                _px /= _pl;
                _py /= _pl;
            }
            _nx = _cx + _px * (_r + 0.01);
            _ny = _cy + _py * (_r + 0.01);
            _pushed = true;
            _stuck = true;
        }
        if (!_pushed)
        {
            _stuck = false;
            break;
        }
    }
    return [_nx, _ny, _stuck];
}

/// @desc Move the pawn by (_dx, _dy) with collision and sliding, firing walk
/// actions on every edge its centre crosses.
function pawn_move(_w, _dx, _dy)
{
    var _dist = point_distance(0, 0, _dx, _dy);
    if (_dist <= 0)
    {
        return;
    }
    // Small steps, so a thin wall can never be jumped over
    var _steps = max(1, ceil(_dist / (PL_RADIUS * 0.5)));
    for (var _s = 0; _s < _steps; _s++)
    {
        var _ox = pl_x;
        var _oy = pl_y;
        var _res = pawn_resolve(_w, _ox, _oy, _ox + _dx / _steps, _oy + _dy / _steps);
        if (_res[2])
        {
            // Wedged between walls: stay put this step
            continue;
        }
        pl_x = _res[0];
        pl_y = _res[1];
        pawn_walk_triggers(_w, _ox, _oy, pl_x, pl_y);
    }
}

function pawn_walk_triggers(_w, _ox, _oy, _nx, _ny)
{
    var _near = world_edges_near(_w, min(_ox, _nx), min(_oy, _ny), max(_ox, _nx), max(_oy, _ny));
    for (var _i = 0; _i < array_length(_near); _i++)
    {
        var _e = _near[_i];
        var _ed = _w.edges[_e];
        if (_ed.action.trigger != "walk")
        {
            continue;
        }
        var _a = _w.verts[_ed.v0];
        var _b = _w.verts[_ed.v1];
        // Crossed = the centre changed side and the path met the edge
        if (world_edge_side(_w, _e, _ox, _oy) != world_edge_side(_w, _e, _nx, _ny)
            && world_seg_hit(_ox, _oy, _nx, _ny, _a[0], _a[1], _b[0], _b[1]) >= 0)
        {
            action_fire(_w, _e, "walk");
        }
    }
}

/// @desc Floor and ceiling under the pawn's circle: [floorz, ceilz, sector].
function pawn_heights(_w, _px, _py, _feet)
{
    var _s = world_sector_at(_w, _px, _py, _feet);
    var _fl = _feet;
    var _ce = _feet + PL_HEAD;
    if (_s >= 0)
    {
        _fl = world_floor_at(_w, _s, _px, _py);
        _ce = world_ceil_at(_w, _s, _px, _py);
    }
    var _r = PL_RADIUS;
    var _near = world_edges_near(_w, _px - _r, _py - _r, _px + _r, _py + _r);
    for (var _i = 0; _i < array_length(_near); _i++)
    {
        var _e = _near[_i];
        var _ed = _w.edges[_e];
        if (_ed.back < 0)
        {
            continue;
        }
        var _a = _w.verts[_ed.v0];
        var _b = _w.verts[_ed.v1];
        var _dx = _b[0] - _a[0];
        var _dy = _b[1] - _a[1];
        var _l2 = max(_dx * _dx + _dy * _dy, 0.0001);
        var _t = clamp(((_px - _a[0]) * _dx + (_py - _a[1]) * _dy) / _l2, 0, 1);
        var _cx = _a[0] + _dx * _t;
        var _cy = _a[1] + _dy * _t;
        if (point_distance(_px, _py, _cx, _cy) >= _r)
        {
            continue;
        }
        var _op = world_opening(_w, _e, _cx, _cy);
        _fl = max(_fl, _op[0]);
        _ce = min(_ce, _op[1]);
    }
    return [_fl, _ce, _s];
}

/// @desc Use key: the first edge with a use action within reach, unless a
/// closed edge is in the way.
function pawn_use(_w)
{
    var _ex = pl_x + dcos(pl_yaw) * PL_USE_RANGE;
    var _ey = pl_y - dsin(pl_yaw) * PL_USE_RANGE;
    var _hits = pawn_trace(_w, pl_x, pl_y, _ex, _ey);
    for (var _i = 0; _i < array_length(_hits); _i++)
    {
        var _e = _hits[_i].e;
        var _ed = _w.edges[_e];
        if (_ed.action.trigger == "use")
        {
            action_fire(_w, _e, "use");
            return;
        }
        if (_ed.back < 0)
        {
            break;
        }
        var _op = world_opening(_w, _e, _hits[_i].x, _hits[_i].y);
        if (_op[1] <= _op[0])
        {
            break;
        }
    }
    _w.last_event = "use: nothing in reach";
}

/// @desc Edges crossed by the segment a -> b, nearest first: [{ e, t, x, y }].
function pawn_trace(_w, _ax, _ay, _bx, _by)
{
    var _near = world_edges_near(_w, min(_ax, _bx), min(_ay, _by), max(_ax, _bx), max(_ay, _by));
    var _hits = [];
    for (var _i = 0; _i < array_length(_near); _i++)
    {
        var _e = _near[_i];
        var _ed = _w.edges[_e];
        var _a = _w.verts[_ed.v0];
        var _b = _w.verts[_ed.v1];
        var _t = world_seg_hit(_ax, _ay, _bx, _by, _a[0], _a[1], _b[0], _b[1]);
        if (_t >= 0)
        {
            array_push(_hits, { e: _e, t: _t, x: _ax + (_bx - _ax) * _t, y: _ay + (_by - _ay) * _t });
        }
    }
    array_sort(_hits, function(_p, _q)
    {
        return _p.t - _q.t;
    });
    return _hits;
}

/// @desc Hitscan along the view: fires the shoot action of the wall it hits.
/// (Weapons and damage come with the enemies milestone.)
function pawn_shoot(_w)
{
    var _cp = dcos(pl_pitch);
    if (_cp < 0.01)
    {
        return;
    }
    var _ex = pl_x + dcos(pl_yaw) * PL_SHOOT_RANGE;
    var _ey = pl_y - dsin(pl_yaw) * PL_SHOOT_RANGE;
    var _slope = dtan(pl_pitch);
    var _hits = pawn_trace(_w, pl_x, pl_y, _ex, _ey);
    var _cur = pl_sector;
    for (var _i = 0; _i < array_length(_hits); _i++)
    {
        var _h = _hits[_i];
        var _ed = _w.edges[_h.e];
        var _z = pl_view_z + _h.t * PL_SHOOT_RANGE * _slope;
        // Into the floor or ceiling of the sector the shot is in?
        if (_cur >= 0 && (_z < world_floor_at(_w, _cur, _h.x, _h.y) || _z > world_ceil_at(_w, _cur, _h.x, _h.y)))
        {
            _w.last_event = "shot hit a floor / ceiling";
            return;
        }
        var _wall = (_ed.back < 0);
        if (!_wall)
        {
            var _op = world_opening(_w, _h.e, _h.x, _h.y);
            if (_z < _op[0] || _z > _op[1])
            {
                _wall = true;
            }
        }
        if (_wall)
        {
            if (!action_fire(_w, _h.e, "shoot"))
            {
                _w.last_event = "shot hit edge " + string(_h.e);
            }
            return;
        }
        if (_cur == _ed.front)
        {
            _cur = _ed.back;
        }
        else
        {
            _cur = _ed.front;
        }
    }
    _w.last_event = "shot hit nothing";
}

/// @desc Mouse capture, look, use / shoot and movement. Call once per Step.
function pawn_update(_w)
{
    // --- Mouse capture ---
    var _clicked = mouse_check_button_pressed(mb_left);
    if (!mouse_captured && _clicked)
    {
        mouse_captured = true;
        window_mouse_set_locked(true);
        _clicked = false;
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

    // --- Use / shoot ---
    if (keyboard_check_pressed(ord("E")))
    {
        pawn_use(_w);
    }
    if ((mouse_captured && _clicked) || keyboard_check_pressed(vk_control))
    {
        pawn_shoot(_w);
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
    var _up = keyboard_check(vk_space) - keyboard_check(ord("C"));
    pawn_walk(_w, _fwd, _side, _up, _speed);
}

/// @desc Move by intent: _fwd / _side / _up in -1..1 (up only flies in noclip).
/// The keyboard and the self-test's walk script both come through here.
function pawn_walk(_w, _fwd, _side, _up, _speed)
{
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
        pl_z += _up * _speed;
        pl_view_z = pl_z + PL_EYE;
        pl_sector = world_sector_at(_w, pl_x, pl_y, pl_z);
        return;
    }

    pawn_move(_w, _dx, _dy);
    pawn_settle(_w);
}

/// @desc Floor, steps, falling, lifts and ceilings, then the eye. Also runs
/// after movers so the pawn rides lifts.
function pawn_settle(_w)
{
    var _hz = pawn_heights(_w, pl_x, pl_y, pl_z);
    pl_floorz = _hz[0];
    pl_ceilz = _hz[1];
    pl_sector = _hz[2];

    if (pl_z < pl_floorz)
    {
        // Step up (or carried up by a floor); the eye eases up after it
        pl_z = pl_floorz;
        pl_vz = 0;
    }
    else if (pl_on_ground && pl_z - pl_floorz <= PL_STICK)
    {
        // Down a slope or riding a lift down
        pl_z = pl_floorz;
        pl_vz = 0;
    }
    else if (pl_z > pl_floorz)
    {
        pl_vz -= _w.gravity;
        pl_z += pl_vz;
        if (pl_z <= pl_floorz)
        {
            pl_z = pl_floorz;
            pl_vz = 0;
        }
    }
    pl_on_ground = (pl_z <= pl_floorz);

    if (pl_z + PL_HEAD > pl_ceilz)
    {
        // Squeezed (a crusher on the way down): stay on the floor
        pl_z = max(pl_floorz, min(pl_z, pl_ceilz - PL_HEAD));
        pl_vz = min(pl_vz, 0);
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
    pl_view_z = min(pl_view_z, pl_ceilz - 4);
}

/// @desc View matrix for the pawn's eye (+Z up).
function pawn_view_matrix()
{
    var _lx = dcos(pl_yaw) * dcos(pl_pitch);
    var _ly = -dsin(pl_yaw) * dcos(pl_pitch);
    var _lz = dsin(pl_pitch);
    return matrix_build_lookat(pl_x, pl_y, pl_view_z, pl_x + _lx, pl_y + _ly, pl_view_z + _lz, 0, 0, 1);
}
