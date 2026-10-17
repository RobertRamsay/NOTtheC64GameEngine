/// scr_vis
/// Portal visibility (docs/ENGINE_DESIGN.md §4). Each frame, flood from the
/// camera's sector through portals. Every sector carries a screen window (a
/// rectangle in -1..1 screen units); a portal's opening is projected, clipped to
/// the window of the sector it is seen from, and what is left becomes (part of)
/// the window of the sector behind it. Closed doors stop the flood. Only groups
/// that hold a reached sector are drawn.
///
/// The screen units are our own (from yaw / pitch and RENDER_FOV), not
/// GameMaker's matrices, so they only have to agree with themselves.

/// Camera this close (plan units) to a portal passes its whole window through.
#macro VIS_NEAR 16
/// Near plane for clipping portal openings (view units).
#macro VIS_ZNEAR 1
/// How often one sector may be re-entered with a bigger window.
#macro VIS_MAX_VISITS 8

/// @desc Mark every sector and group visible.
function vis_all(_w)
{
    for (var _s = 0; _s < _w.nsec; _s++)
    {
        _w.vis[_s] = true;
    }
    for (var _g = 0; _g < array_length(_w.groups); _g++)
    {
        _w.group_vis[_g] = true;
    }
    _w.vis_count = _w.nsec;
    _w.vis_groups = array_length(_w.groups);
}

/// @desc Project the 3D quad a -> b between bottom and top heights. Returns
/// [x0, x1, y0, y1] in screen units, or undefined when it is behind the eye.
function vis_project_quad(_w, _ax, _ay, _bx, _by, _bot_a, _bot_b, _top_a, _top_b)
{
    var _qx = [_ax, _bx, _bx, _ax];
    var _qy = [_ay, _by, _by, _ay];
    var _qz = [_bot_a, _bot_b, _top_b, _top_a];
    var _f = _w.vis_f;
    var _r = _w.vis_r;
    var _u = _w.vis_u;
    var _vx = array_create(4, 0);
    var _vy = array_create(4, 0);
    var _vz = array_create(4, 0);
    for (var _i = 0; _i < 4; _i++)
    {
        var _dx = _qx[_i] - _w.vis_ex;
        var _dy = _qy[_i] - _w.vis_ey;
        var _dz = _qz[_i] - _w.vis_ez;
        _vx[_i] = _dx * _r[0] + _dy * _r[1] + _dz * _r[2];
        _vy[_i] = _dx * _u[0] + _dy * _u[1] + _dz * _u[2];
        _vz[_i] = _dx * _f[0] + _dy * _f[1] + _dz * _f[2];
    }
    // Clip against the near plane, then take the bounding box on screen
    var _x0 = infinity;
    var _x1 = -infinity;
    var _y0 = infinity;
    var _y1 = -infinity;
    var _any = false;
    for (var _i = 0; _i < 4; _i++)
    {
        var _j = (_i + 1) mod 4;
        var _in_i = (_vz[_i] >= VIS_ZNEAR);
        var _in_j = (_vz[_j] >= VIS_ZNEAR);
        if (_in_i)
        {
            var _sx = _vx[_i] / (_vz[_i] * _w.vis_th);
            var _sy = _vy[_i] / (_vz[_i] * _w.vis_tv);
            _x0 = min(_x0, _sx);
            _x1 = max(_x1, _sx);
            _y0 = min(_y0, _sy);
            _y1 = max(_y1, _sy);
            _any = true;
        }
        if (_in_i != _in_j)
        {
            var _t = (VIS_ZNEAR - _vz[_i]) / (_vz[_j] - _vz[_i]);
            var _cx = _vx[_i] + (_vx[_j] - _vx[_i]) * _t;
            var _cy = _vy[_i] + (_vy[_j] - _vy[_i]) * _t;
            var _sx = _cx / (VIS_ZNEAR * _w.vis_th);
            var _sy = _cy / (VIS_ZNEAR * _w.vis_tv);
            _x0 = min(_x0, _sx);
            _x1 = max(_x1, _sx);
            _y0 = min(_y0, _sy);
            _y1 = max(_y1, _sy);
            _any = true;
        }
    }
    if (!_any)
    {
        return undefined;
    }
    return [_x0, _x1, _y0, _y1];
}

/// @desc Work out which sectors and groups are visible from the eye at
/// (_ex, _ey, _ez) looking along _yaw / _pitch. _feet picks the camera's sector.
function vis_update(_w, _ex, _ey, _ez, _yaw, _pitch, _feet)
{
    var _start = world_sector_at(_w, _ex, _ey, _feet);
    if (!_w.vis_on || _start < 0)
    {
        vis_all(_w);
        return;
    }
    var _n = _w.nsec;
    for (var _s = 0; _s < _n; _s++)
    {
        _w.vis[_s] = false;
        _w.vis_visits[_s] = 0;
    }

    // Camera basis (+Z up): forward, right, up
    var _cp = dcos(_pitch);
    var _sp = dsin(_pitch);
    var _cy = dcos(_yaw);
    var _sy = dsin(_yaw);
    _w.vis_ex = _ex;
    _w.vis_ey = _ey;
    _w.vis_ez = _ez;
    _w.vis_f = [_cy * _cp, -_sy * _cp, _sp];
    _w.vis_r = [-_sy, -_cy, 0];
    _w.vis_u = [-_cy * _sp, _sy * _sp, _cp];
    _w.vis_th = dtan(RENDER_FOV / 2);
    _w.vis_tv = _w.vis_th * RENDER_H / RENDER_W;

    _w.vis[_start] = true;
    _w.vis_wx0[_start] = -1;
    _w.vis_wx1[_start] = 1;
    _w.vis_wy0[_start] = -1;
    _w.vis_wy1[_start] = 1;
    var _stack = [_start];

    while (array_length(_stack) > 0)
    {
        var _s = array_pop(_stack);
        var _wx0 = _w.vis_wx0[_s];
        var _wx1 = _w.vis_wx1[_s];
        var _wy0 = _w.vis_wy0[_s];
        var _wy1 = _w.vis_wy1[_s];
        var _hs = _w.sec[_s].halfs;
        for (var _h = 0; _h < array_length(_hs); _h++)
        {
            var _e = _hs[_h].e;
            var _k = _hs[_h].k;
            var _ed = _w.edges[_e];
            if (_ed.back < 0)
            {
                continue;
            }
            var _o = _ed.back;
            if (_k == 1)
            {
                _o = _ed.front;
            }
            if (_o == _s)
            {
                continue;
            }
            var _va = _w.verts[world_half_from(_w, _e, _k)];
            var _vb = _w.verts[world_half_to(_w, _e, _k)];
            var _ax = _va[0];
            var _ay = _va[1];
            var _bx = _vb[0];
            var _by = _vb[1];

            // The opening, as it is right now (closed doors block)
            var _oa = world_opening(_w, _e, _ax, _ay);
            var _ob = world_opening(_w, _e, _bx, _by);
            if (_oa[1] <= _oa[0] && _ob[1] <= _ob[0])
            {
                continue;
            }

            var _nx0 = _wx0;
            var _nx1 = _wx1;
            var _ny0 = _wy0;
            var _ny1 = _wy1;
            var _dx = _bx - _ax;
            var _dy = _by - _ay;
            var _l2 = max(_dx * _dx + _dy * _dy, 0.0001);
            var _t = clamp(((_ex - _ax) * _dx + (_ey - _ay) * _dy) / _l2, 0, 1);
            var _near = point_distance(_ex, _ey, _ax + _dx * _t, _ay + _dy * _t);
            if (_near >= VIS_NEAR)
            {
                // Only portals that face the eye (it is on this sector's side)
                if (tri_orient(_ax, _ay, _bx, _by, _ex, _ey) <= 0)
                {
                    continue;
                }
                var _rc = vis_project_quad(_w, _ax, _ay, _bx, _by, _oa[0], _ob[0], _oa[1], _ob[1]);
                if (is_undefined(_rc))
                {
                    continue;
                }
                _nx0 = max(_wx0, _rc[0]);
                _nx1 = min(_wx1, _rc[1]);
                _ny0 = max(_wy0, _rc[2]);
                _ny1 = min(_wy1, _rc[3]);
                if (_nx0 >= _nx1 || _ny0 >= _ny1)
                {
                    continue;
                }
            }

            if (!_w.vis[_o])
            {
                _w.vis[_o] = true;
                _w.vis_wx0[_o] = _nx0;
                _w.vis_wx1[_o] = _nx1;
                _w.vis_wy0[_o] = _ny0;
                _w.vis_wy1[_o] = _ny1;
                _w.vis_visits[_o] = 1;
                array_push(_stack, _o);
            }
            else if (_nx0 < _w.vis_wx0[_o] || _nx1 > _w.vis_wx1[_o] || _ny0 < _w.vis_wy0[_o] || _ny1 > _w.vis_wy1[_o])
            {
                // Seen through another portal too: grow its window and go again
                _w.vis_wx0[_o] = min(_w.vis_wx0[_o], _nx0);
                _w.vis_wx1[_o] = max(_w.vis_wx1[_o], _nx1);
                _w.vis_wy0[_o] = min(_w.vis_wy0[_o], _ny0);
                _w.vis_wy1[_o] = max(_w.vis_wy1[_o], _ny1);
                if (_w.vis_visits[_o] < VIS_MAX_VISITS)
                {
                    _w.vis_visits[_o] += 1;
                    array_push(_stack, _o);
                }
            }
        }
    }

    _w.vis_count = 0;
    for (var _s = 0; _s < _n; _s++)
    {
        if (_w.vis[_s])
        {
            _w.vis_count += 1;
        }
    }
    _w.vis_groups = 0;
    for (var _g = 0; _g < array_length(_w.groups); _g++)
    {
        var _sl = _w.groups[_g].sectors;
        var _gv = false;
        for (var _i = 0; _i < array_length(_sl); _i++)
        {
            if (_w.vis[_sl[_i]])
            {
                _gv = true;
                break;
            }
        }
        _w.group_vis[_g] = _gv;
        if (_gv)
        {
            _w.vis_groups += 1;
        }
    }
}
