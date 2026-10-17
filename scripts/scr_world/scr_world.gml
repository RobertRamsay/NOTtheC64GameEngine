/// scr_world
/// The world runtime: a v1 level (scr_level) baked into what the engine draws
/// and collides with. Sectors + portals, Doom / Build style, drawn as true 3D.
///
/// world_bake(level) returns the world struct:
///   sec[]      runtime sectors: loops (outer loops + holes, traced from the
///              edges), floor / ceiling planes [a, b, c] (z = a*x + b*y + c,
///              slopes), mover offsets foff / coff and their ranges, half-edges.
///   groups[]   static geometry, a few neighbouring sectors per group, one frozen
///              vertex buffer per texture. Only groups with a visible sector are
///              drawn (scr_vis).
///   planes[]   geometry that moves with a sector's floor or ceiling (doors,
///              lifts...): small buffers drawn with a translate matrix.
///   movers[]   active movers (scr_mover).
///   blockmap   WORLD_BLOCK-unit grid of edges for collision and traces.
///
/// Walls next to a moving plane: the face whose visible edge *is* the moving
/// plane goes into that plane's buffer (it slides with it); every other wall is
/// static and baked over the plane's whole travel, the part beyond the plane
/// being hidden behind that plane's floor or ceiling.

#macro WORLD_GROUP_SECTORS 4
#macro WORLD_BLOCK 128

function world_init()
{
    vertex_format_begin();
    vertex_format_add_position_3d();
    vertex_format_add_colour();
    vertex_format_add_texcoord();
    global.WORLD_VFORMAT = vertex_format_end();
}

// ============================================================
//  BAKE
// ============================================================

/// @desc Bake a v1 level into a world. Static geometry is frozen once here.
function world_bake(_lv)
{
    var _ne = array_length(_lv.edges);
    var _w = {
        level: _lv,
        verts: _lv.vertices,
        edges: _lv.edges,
        nsec: array_length(_lv.sectors),
        sec: [],
        groups: [],
        planes: [],
        movers: [],
        tris: 0,
        nbatches: 0,
        drawn: 0,
        bm_x0: 0,
        bm_y0: 0,
        bm_cols: 1,
        bm_rows: 1,
        bm_cells: [],
        stamp: array_create(_ne, 0),
        stamp_id: 0,
        edge_used: array_create(_ne, false),
        last_event: "",
        falloff: _lv.settings.fog,
        gravity: _lv.settings.gravity,
        vis_on: true,
        vis: [],
        vis_wx0: [],
        vis_wx1: [],
        vis_wy0: [],
        vis_wy1: [],
        vis_visits: [],
        group_vis: [],
        vis_count: 0,
        vis_groups: 0,
        vis_ex: 0,
        vis_ey: 0,
        vis_ez: 0,
        vis_f: [1, 0, 0],
        vis_r: [0, 1, 0],
        vis_u: [0, 0, 1],
        vis_th: 1,
        vis_tv: 1
    };
    world_build_sectors(_w);
    mover_bake_ranges(_w);
    world_build_groups(_w);
    world_build_geometry(_w);
    world_build_blockmap(_w);

    var _n = _w.nsec;
    _w.vis = array_create(_n, true);
    _w.vis_wx0 = array_create(_n, 0);
    _w.vis_wx1 = array_create(_n, 0);
    _w.vis_wy0 = array_create(_n, 0);
    _w.vis_wy1 = array_create(_n, 0);
    _w.vis_visits = array_create(_n, 0);
    _w.group_vis = array_create(array_length(_w.groups), true);
    return _w;
}

/// @desc Start and end vertex of edge _e seen from side _k (0 front, 1 back).
/// The side's sector is always on the right of from -> to.
function world_half_from(_w, _e, _k)
{
    if (_k == 0)
    {
        return _w.edges[_e].v0;
    }
    return _w.edges[_e].v1;
}

function world_half_to(_w, _e, _k)
{
    if (_k == 0)
    {
        return _w.edges[_e].v1;
    }
    return _w.edges[_e].v0;
}

/// @desc Plane [a, b, c] for a sector surface at _base with slope _slope.
function world_slope_plane(_w, _s, _slope, _base, _loops)
{
    var _flat = [0, 0, _base];
    var _e = _slope.edge;
    if (_e < 0 || _e >= array_length(_w.edges) || _slope.rise == 0)
    {
        return _flat;
    }
    var _ed = _w.edges[_e];
    if (_ed.front < 0 || (_ed.front != _s && _ed.back != _s) || _ed.front == _ed.back)
    {
        show_debug_message("world_bake: sector " + string(_s) + " slope edge " + string(_e) + " is not one of its edges");
        return _flat;
    }
    var _a = _w.verts[_ed.v0];
    var _b = _w.verts[_ed.v1];
    var _len = point_distance(_a[0], _a[1], _b[0], _b[1]);
    if (_len <= 0)
    {
        return _flat;
    }
    // Unit normal into the sector (the front is on the right of v0 -> v1)
    var _nx = -(_b[1] - _a[1]) / _len;
    var _ny = (_b[0] - _a[0]) / _len;
    if (_ed.front != _s)
    {
        _nx = -_nx;
        _ny = -_ny;
    }
    var _far = 0;
    for (var _l = 0; _l < array_length(_loops); _l++)
    {
        var _lp = _loops[_l];
        for (var _i = 0; _i < array_length(_lp) div 2; _i++)
        {
            _far = max(_far, (_lp[_i * 2] - _a[0]) * _nx + (_lp[_i * 2 + 1] - _a[1]) * _ny);
        }
    }
    if (_far < 0.001)
    {
        return _flat;
    }
    var _gx = _nx * _slope.rise / _far;
    var _gy = _ny * _slope.rise / _far;
    return [_gx, _gy, _base - _gx * _a[0] - _gy * _a[1]];
}

function world_plane_z(_p, _px, _py)
{
    return _p[0] * _px + _p[1] * _py + _p[2];
}

/// @desc Trace a sector's loops from its half-edges (sector on the right).
function world_sector_loops(_w, _s)
{
    var _hs = _w.sec[_s].halfs;
    var _n = array_length(_hs);
    var _used = array_create(_n, false);
    var _from = {};
    for (var _i = 0; _i < _n; _i++)
    {
        var _k = string(world_half_from(_w, _hs[_i].e, _hs[_i].k));
        if (is_undefined(_from[$ _k]))
        {
            _from[$ _k] = [];
        }
        array_push(_from[$ _k], _i);
    }

    var _loops = [];
    for (var _i = 0; _i < _n; _i++)
    {
        if (_used[_i])
        {
            continue;
        }
        var _pts = [];
        var _cur = _i;
        var _start = world_half_from(_w, _hs[_i].e, _hs[_i].k);
        var _closed = false;
        var _guard = _n + 1;
        while (_guard > 0)
        {
            _guard -= 1;
            _used[_cur] = true;
            var _fv = world_half_from(_w, _hs[_cur].e, _hs[_cur].k);
            var _tv = world_half_to(_w, _hs[_cur].e, _hs[_cur].k);
            array_push(_pts, _w.verts[_fv][0], _w.verts[_fv][1]);
            if (_tv == _start)
            {
                _closed = true;
                break;
            }
            var _cands = _from[$ string(_tv)];
            if (is_undefined(_cands))
            {
                break;
            }
            // Where loops of one sector touch, take the sharpest right turn
            var _pick = -1;
            var _best = -infinity;
            var _ix = _w.verts[_tv][0] - _w.verts[_fv][0];
            var _iy = _w.verts[_tv][1] - _w.verts[_fv][1];
            for (var _c = 0; _c < array_length(_cands); _c++)
            {
                var _h = _cands[_c];
                if (_used[_h])
                {
                    continue;
                }
                var _nv = world_half_to(_w, _hs[_h].e, _hs[_h].k);
                var _ox = _w.verts[_nv][0] - _w.verts[_tv][0];
                var _oy = _w.verts[_nv][1] - _w.verts[_tv][1];
                var _ang = darctan2(_ix * _oy - _iy * _ox, _ix * _ox + _iy * _oy);
                if (_ang > _best)
                {
                    _best = _ang;
                    _pick = _h;
                }
            }
            if (_pick < 0)
            {
                break;
            }
            _cur = _pick;
        }
        if (_closed && array_length(_pts) >= 6)
        {
            array_push(_loops, _pts);
        }
        else
        {
            show_debug_message("world_bake: sector " + string(_s) + " has an unclosed loop");
        }
    }
    return _loops;
}

function world_build_sectors(_w)
{
    var _lv = _w.level;
    for (var _s = 0; _s < _w.nsec; _s++)
    {
        var _d = _lv.sectors[_s];
        array_push(_w.sec, {
            floor: _d.floor,
            ceil: _d.ceil,
            light: _d.light,
            tag: _d.tag,
            ftex: _d.ftex,
            ctex: _d.ctex,
            fp: [0, 0, _d.floor],
            cp: [0, 0, _d.ceil],
            foff: 0,
            coff: 0,
            fmin: 0,
            fmax: 0,
            cmin: 0,
            cmax: 0,
            fmv: undefined,
            cmv: undefined,
            loops: [],
            halfs: [],
            nbs: [],
            x0: 0,
            y0: 0,
            x1: 0,
            y1: 0,
            group: -1,
            fgeo: -1,
            cgeo: -1
        });
    }
    for (var _e = 0; _e < array_length(_w.edges); _e++)
    {
        var _ed = _w.edges[_e];
        if (_ed.front < 0)
        {
            continue;
        }
        array_push(_w.sec[_ed.front].halfs, { e: _e, k: 0 });
        if (_ed.back >= 0)
        {
            array_push(_w.sec[_ed.back].halfs, { e: _e, k: 1 });
            if (_ed.back != _ed.front)
            {
                world_add_unique(_w.sec[_ed.front].nbs, _ed.back);
                world_add_unique(_w.sec[_ed.back].nbs, _ed.front);
            }
        }
    }
    for (var _s = 0; _s < _w.nsec; _s++)
    {
        var _rs = _w.sec[_s];
        _rs.loops = world_sector_loops(_w, _s);
        _rs.x0 = infinity;
        _rs.y0 = infinity;
        _rs.x1 = -infinity;
        _rs.y1 = -infinity;
        for (var _l = 0; _l < array_length(_rs.loops); _l++)
        {
            var _lp = _rs.loops[_l];
            for (var _i = 0; _i < array_length(_lp) div 2; _i++)
            {
                _rs.x0 = min(_rs.x0, _lp[_i * 2]);
                _rs.y0 = min(_rs.y0, _lp[_i * 2 + 1]);
                _rs.x1 = max(_rs.x1, _lp[_i * 2]);
                _rs.y1 = max(_rs.y1, _lp[_i * 2 + 1]);
            }
        }
        var _d = _w.level.sectors[_s];
        _rs.fp = world_slope_plane(_w, _s, _d.fslope, _d.floor, _rs.loops);
        _rs.cp = world_slope_plane(_w, _s, _d.cslope, _d.ceil, _rs.loops);
    }
}

function world_add_unique(_arr, _v)
{
    for (var _i = 0; _i < array_length(_arr); _i++)
    {
        if (_arr[_i] == _v)
        {
            return;
        }
    }
    array_push(_arr, _v);
}

/// @desc Group neighbouring sectors (breadth first) so visibility can skip
/// whole groups while the number of vertex_submit calls stays small.
function world_build_groups(_w)
{
    for (var _s = 0; _s < _w.nsec; _s++)
    {
        if (_w.sec[_s].group >= 0)
        {
            continue;
        }
        var _g = array_length(_w.groups);
        var _grp = { sectors: [], bs: {}, batches: [] };
        array_push(_w.groups, _grp);
        var _queue = [_s];
        var _qi = 0;
        while (_qi < array_length(_queue) && array_length(_grp.sectors) < WORLD_GROUP_SECTORS)
        {
            var _q = _queue[_qi];
            _qi += 1;
            if (_w.sec[_q].group >= 0)
            {
                continue;
            }
            _w.sec[_q].group = _g;
            array_push(_grp.sectors, _q);
            var _nbs = _w.sec[_q].nbs;
            for (var _i = 0; _i < array_length(_nbs); _i++)
            {
                if (_w.sec[_nbs[_i]].group < 0)
                {
                    array_push(_queue, _nbs[_i]);
                }
            }
        }
    }
}

/// @desc Batch set of the moving plane of sector _s (floor, or ceiling when
/// _ceil), created on first use. _seen_from is a sector that must be visible
/// for this geometry to be drawn.
function world_plane_bs(_w, _s, _ceil, _seen_from)
{
    var _rs = _w.sec[_s];
    var _pi = _rs.fgeo;
    if (_ceil)
    {
        _pi = _rs.cgeo;
    }
    if (_pi < 0)
    {
        _pi = array_length(_w.planes);
        array_push(_w.planes, { sector: _s, ceil: _ceil, bs: {}, batches: [], seen: [_s] });
        if (_ceil)
        {
            _rs.cgeo = _pi;
        }
        else
        {
            _rs.fgeo = _pi;
        }
    }
    world_add_unique(_w.planes[_pi].seen, _seen_from);
    return _w.planes[_pi].bs;
}

function world_group_bs(_w, _s)
{
    return _w.groups[_w.sec[_s].group].bs;
}

/// @desc Get (or start) the vertex buffer batch for texture _name in batch set _bs.
function world_batch(_bs, _name)
{
    var _b = _bs[$ _name];
    if (is_undefined(_b))
    {
        var _vb = vertex_create_buffer();
        vertex_begin(_vb, global.WORLD_VFORMAT);
        _b = { name: _name, vb: _vb, tris: 0 };
        _bs[$ _name] = _b;
    }
    return _b;
}

/// @desc Close every batch of a set: freeze the non-empty ones, return them sorted.
function world_finish_batches(_w, _bs)
{
    var _out = [];
    var _names = struct_get_names(_bs);
    array_sort(_names, true);
    for (var _i = 0; _i < array_length(_names); _i++)
    {
        var _b = _bs[$ _names[_i]];
        vertex_end(_b.vb);
        if (_b.tris > 0)
        {
            vertex_freeze(_b.vb);
            array_push(_out, _b);
            _w.tris += _b.tris;
            _w.nbatches += 1;
        }
        else
        {
            vertex_delete_buffer(_b.vb);
        }
    }
    return _out;
}

function world_vert(_vb, _wx, _wy, _wz, _shade, _u, _v)
{
    var _l = clamp(round(_shade * 255), 0, 255);
    vertex_position_3d(_vb, _wx, _wy, _wz);
    vertex_colour(_vb, make_colour_rgb(_l, _l, _l), 1);
    vertex_texcoord(_vb, _u, _v);
}

/// @desc A wall piece along a -> b whose bottom and top heights are given at
/// both ends. Only the part where top > bottom is drawn (split where they cross).
/// _sd is the level side (texture offsets and scale).
function world_span(_bs, _tex, _ax, _ay, _bx, _by, _bot_a, _bot_b, _top_a, _top_b, _shade, _sd)
{
    var _da = _top_a - _bot_a;
    var _db = _top_b - _bot_b;
    if (_da <= 0 && _db <= 0)
    {
        return;
    }
    var _b = world_batch(_bs, _tex);
    var _buf = _b.vb;
    var _len = point_distance(_ax, _ay, _bx, _by);
    var _su = 1 / (TEX_WORLD * max(_sd.sx, 0.01));
    var _sv = 1 / (TEX_WORLD * max(_sd.sy, 0.01));
    var _ua = _sd.ox * _su;
    var _ub = (_len + _sd.ox) * _su;
    var _oy = _sd.oy;
    if (_da >= 0 && _db >= 0)
    {
        world_vert(_buf, _ax, _ay, _top_a, _shade, _ua, (_oy - _top_a) * _sv);
        world_vert(_buf, _bx, _by, _top_b, _shade, _ub, (_oy - _top_b) * _sv);
        world_vert(_buf, _bx, _by, _bot_b, _shade, _ub, (_oy - _bot_b) * _sv);
        world_vert(_buf, _ax, _ay, _top_a, _shade, _ua, (_oy - _top_a) * _sv);
        world_vert(_buf, _bx, _by, _bot_b, _shade, _ub, (_oy - _bot_b) * _sv);
        world_vert(_buf, _ax, _ay, _bot_a, _shade, _ua, (_oy - _bot_a) * _sv);
        _b.tris += 2;
        return;
    }
    var _t = _da / (_da - _db);
    var _mx = _ax + (_bx - _ax) * _t;
    var _my = _ay + (_by - _ay) * _t;
    var _mz = _bot_a + (_bot_b - _bot_a) * _t;
    var _um = (_t * _len + _sd.ox) * _su;
    if (_da > 0)
    {
        world_vert(_buf, _ax, _ay, _top_a, _shade, _ua, (_oy - _top_a) * _sv);
        world_vert(_buf, _mx, _my, _mz, _shade, _um, (_oy - _mz) * _sv);
        world_vert(_buf, _ax, _ay, _bot_a, _shade, _ua, (_oy - _bot_a) * _sv);
    }
    else
    {
        world_vert(_buf, _mx, _my, _mz, _shade, _um, (_oy - _mz) * _sv);
        world_vert(_buf, _bx, _by, _top_b, _shade, _ub, (_oy - _top_b) * _sv);
        world_vert(_buf, _bx, _by, _bot_b, _shade, _ub, (_oy - _bot_b) * _sv);
    }
    _b.tris += 1;
}

/// @desc Triangles (flat [x, y] list) on plane _p.
function world_flat(_bs, _tex, _tris, _p, _shade)
{
    if (array_length(_tris) < 6 || _tex == "")
    {
        return;
    }
    var _b = world_batch(_bs, _tex);
    var _buf = _b.vb;
    for (var _i = 0; _i < array_length(_tris) div 2; _i++)
    {
        var _px = _tris[_i * 2];
        var _py = _tris[_i * 2 + 1];
        world_vert(_buf, _px, _py, world_plane_z(_p, _px, _py), _shade, _px / TEX_WORLD, _py / TEX_WORLD);
    }
    _b.tris += array_length(_tris) div 6;
}

/// @desc Walls of edge _e seen from side _k (sector _ss), _so on the other side (-1 = none).
function world_side_walls(_w, _e, _k, _ss, _so)
{
    var _ed = _w.edges[_e];
    var _sd = _ed.sides[_k];
    var _va = _w.verts[world_half_from(_w, _e, _k)];
    var _vb = _w.verts[world_half_to(_w, _e, _k)];
    var _ax = _va[0];
    var _ay = _va[1];
    var _bx = _vb[0];
    var _by = _vb[1];
    var _rs = _w.sec[_ss];
    // Doom's fake contrast: walls along X a little brighter than walls along Y
    var _len = max(point_distance(_ax, _ay, _bx, _by), 1);
    var _shade = _rs.light * (0.8 + 0.2 * abs(_bx - _ax) / _len);
    var _sfa = world_plane_z(_rs.fp, _ax, _ay);
    var _sfb = world_plane_z(_rs.fp, _bx, _by);
    var _sca = world_plane_z(_rs.cp, _ax, _ay);
    var _scb = world_plane_z(_rs.cp, _bx, _by);

    if (_so < 0)
    {
        if (_sd.middle != "")
        {
            world_span(world_group_bs(_w, _ss), _sd.middle, _ax, _ay, _bx, _by,
                _sfa + _rs.fmin, _sfb + _rs.fmin, _sca + _rs.cmax, _scb + _rs.cmax, _shade, _sd);
        }
        return;
    }

    var _ro = _w.sec[_so];
    var _ofa = world_plane_z(_ro.fp, _ax, _ay);
    var _ofb = world_plane_z(_ro.fp, _bx, _by);
    var _oca = world_plane_z(_ro.cp, _ax, _ay);
    var _ocb = world_plane_z(_ro.cp, _bx, _by);

    // Lower wall: up from this floor to the other sector's floor
    if (_sd.lower != "")
    {
        if (_ro.fmin != _ro.fmax)
        {
            // Its top is the other (moving) floor: slide with it
            var _drop = _rs.fmin - _ro.fmax;
            world_span(world_plane_bs(_w, _so, false, _ss), _sd.lower, _ax, _ay, _bx, _by,
                _sfa + _drop, _sfb + _drop, _ofa, _ofb, _shade, _sd);
        }
        else
        {
            world_span(world_group_bs(_w, _ss), _sd.lower, _ax, _ay, _bx, _by,
                _sfa + _rs.fmin, _sfb + _rs.fmin, _ofa, _ofb, _shade, _sd);
        }
    }

    // Upper wall: down from this ceiling to the other sector's ceiling
    if (_sd.upper != "")
    {
        if (_ro.cmin != _ro.cmax)
        {
            var _rise = _rs.cmax - _ro.cmin;
            world_span(world_plane_bs(_w, _so, true, _ss), _sd.upper, _ax, _ay, _bx, _by,
                _oca, _ocb, _sca + _rise, _scb + _rise, _shade, _sd);
        }
        else
        {
            world_span(world_group_bs(_w, _ss), _sd.upper, _ax, _ay, _bx, _by,
                _oca, _ocb, _sca + _rs.cmax, _scb + _rs.cmax, _shade, _sd);
        }
    }
}

/// @desc See-through middle texture of a two-sided edge (grates, fences), drawn
/// once, inside the part of the opening that stays open whatever moves.
function world_mid_wall(_w, _e)
{
    var _ed = _w.edges[_e];
    var _k = 0;
    if (_ed.sides[0].middle == "")
    {
        _k = 1;
    }
    var _sd = _ed.sides[_k];
    if (_sd.middle == "")
    {
        return;
    }
    var _ss = _ed.front;
    if (_k == 1)
    {
        _ss = _ed.back;
    }
    var _va = _w.verts[world_half_from(_w, _e, _k)];
    var _vb = _w.verts[world_half_to(_w, _e, _k)];
    var _rf = _w.sec[_ed.front];
    var _rb = _w.sec[_ed.back];
    var _bot_a = max(world_plane_z(_rf.fp, _va[0], _va[1]) + _rf.fmax, world_plane_z(_rb.fp, _va[0], _va[1]) + _rb.fmax);
    var _bot_b = max(world_plane_z(_rf.fp, _vb[0], _vb[1]) + _rf.fmax, world_plane_z(_rb.fp, _vb[0], _vb[1]) + _rb.fmax);
    var _top_a = min(world_plane_z(_rf.cp, _va[0], _va[1]) + _rf.cmin, world_plane_z(_rb.cp, _va[0], _va[1]) + _rb.cmin);
    var _top_b = min(world_plane_z(_rf.cp, _vb[0], _vb[1]) + _rf.cmin, world_plane_z(_rb.cp, _vb[0], _vb[1]) + _rb.cmin);
    var _len = max(point_distance(_va[0], _va[1], _vb[0], _vb[1]), 1);
    var _rs = _w.sec[_ss];
    var _shade = _rs.light * (0.8 + 0.2 * abs(_vb[0] - _va[0]) / _len);
    world_span(world_group_bs(_w, _ss), _sd.middle, _va[0], _va[1], _vb[0], _vb[1], _bot_a, _bot_b, _top_a, _top_b, _shade, _sd);
}

function world_build_geometry(_w)
{
    for (var _s = 0; _s < _w.nsec; _s++)
    {
        var _rs = _w.sec[_s];
        var _tris = tri_sector(_rs.loops);
        var _bs = world_group_bs(_w, _s);
        if (_rs.fmin != _rs.fmax)
        {
            _bs = world_plane_bs(_w, _s, false, _s);
        }
        world_flat(_bs, _rs.ftex, _tris, _rs.fp, _rs.light);
        _bs = world_group_bs(_w, _s);
        if (_rs.cmin != _rs.cmax)
        {
            _bs = world_plane_bs(_w, _s, true, _s);
        }
        world_flat(_bs, _rs.ctex, _tris, _rs.cp, _rs.light * 0.85);
    }

    for (var _e = 0; _e < array_length(_w.edges); _e++)
    {
        var _ed = _w.edges[_e];
        if (_ed.front < 0)
        {
            continue;
        }
        world_side_walls(_w, _e, 0, _ed.front, _ed.back);
        if (_ed.back >= 0)
        {
            world_side_walls(_w, _e, 1, _ed.back, _ed.front);
            world_mid_wall(_w, _e);
        }
    }

    for (var _g = 0; _g < array_length(_w.groups); _g++)
    {
        _w.groups[_g].batches = world_finish_batches(_w, _w.groups[_g].bs);
        _w.groups[_g].bs = {};
    }
    for (var _p = 0; _p < array_length(_w.planes); _p++)
    {
        _w.planes[_p].batches = world_finish_batches(_w, _w.planes[_p].bs);
        _w.planes[_p].bs = {};
    }
}

function world_build_blockmap(_w)
{
    var _x0 = infinity;
    var _y0 = infinity;
    var _x1 = -infinity;
    var _y1 = -infinity;
    for (var _i = 0; _i < array_length(_w.verts); _i++)
    {
        _x0 = min(_x0, _w.verts[_i][0]);
        _y0 = min(_y0, _w.verts[_i][1]);
        _x1 = max(_x1, _w.verts[_i][0]);
        _y1 = max(_y1, _w.verts[_i][1]);
    }
    if (_x0 > _x1)
    {
        _x0 = 0;
        _y0 = 0;
        _x1 = 0;
        _y1 = 0;
    }
    _w.bm_x0 = _x0 - 8;
    _w.bm_y0 = _y0 - 8;
    _w.bm_cols = floor((_x1 + 8 - _w.bm_x0) / WORLD_BLOCK) + 1;
    _w.bm_rows = floor((_y1 + 8 - _w.bm_y0) / WORLD_BLOCK) + 1;
    var _cells = array_create(_w.bm_cols * _w.bm_rows, 0);
    for (var _i = 0; _i < array_length(_cells); _i++)
    {
        _cells[_i] = [];
    }
    for (var _e = 0; _e < array_length(_w.edges); _e++)
    {
        var _ed = _w.edges[_e];
        if (_ed.front < 0)
        {
            continue;
        }
        var _a = _w.verts[_ed.v0];
        var _b = _w.verts[_ed.v1];
        var _cx0 = floor((min(_a[0], _b[0]) - _w.bm_x0) / WORLD_BLOCK);
        var _cy0 = floor((min(_a[1], _b[1]) - _w.bm_y0) / WORLD_BLOCK);
        var _cx1 = floor((max(_a[0], _b[0]) - _w.bm_x0) / WORLD_BLOCK);
        var _cy1 = floor((max(_a[1], _b[1]) - _w.bm_y0) / WORLD_BLOCK);
        for (var _cy = _cy0; _cy <= _cy1; _cy++)
        {
            for (var _cx = _cx0; _cx <= _cx1; _cx++)
            {
                array_push(_cells[_cy * _w.bm_cols + _cx], _e);
            }
        }
    }
    _w.bm_cells = _cells;
}

function world_free(_w)
{
    for (var _g = 0; _g < array_length(_w.groups); _g++)
    {
        var _bt = _w.groups[_g].batches;
        for (var _i = 0; _i < array_length(_bt); _i++)
        {
            vertex_delete_buffer(_bt[_i].vb);
        }
        _w.groups[_g].batches = [];
    }
    for (var _p = 0; _p < array_length(_w.planes); _p++)
    {
        var _bt = _w.planes[_p].batches;
        for (var _i = 0; _i < array_length(_bt); _i++)
        {
            vertex_delete_buffer(_bt[_i].vb);
        }
        _w.planes[_p].batches = [];
    }
    _w.tris = 0;
    _w.nbatches = 0;
}

// ============================================================
//  DRAW
// ============================================================

function world_submit_batches(_w, _bt)
{
    for (var _i = 0; _i < array_length(_bt); _i++)
    {
        var _t = tex_get(_bt[_i].name);
        if (is_undefined(_t))
        {
            continue;
        }
        vertex_submit(_bt[_i].vb, pr_trianglelist, _t.tex);
        _w.drawn += 1;
    }
}

/// @desc Submit the visible groups and moving planes. Call with sh_world set,
/// after vis_update.
function world_draw(_w)
{
    _w.drawn = 0;
    for (var _g = 0; _g < array_length(_w.groups); _g++)
    {
        if (_w.group_vis[_g])
        {
            world_submit_batches(_w, _w.groups[_g].batches);
        }
    }
    for (var _p = 0; _p < array_length(_w.planes); _p++)
    {
        var _pl = _w.planes[_p];
        var _seen = false;
        for (var _i = 0; _i < array_length(_pl.seen); _i++)
        {
            if (_w.vis[_pl.seen[_i]])
            {
                _seen = true;
                break;
            }
        }
        if (!_seen)
        {
            continue;
        }
        var _rs = _w.sec[_pl.sector];
        var _off = _rs.foff;
        if (_pl.ceil)
        {
            _off = _rs.coff;
        }
        matrix_set(matrix_world, matrix_build(0, 0, _off, 0, 0, 0, 1, 1, 1));
        world_submit_batches(_w, _pl.batches);
    }
    matrix_set(matrix_world, matrix_build_identity());
}

// ============================================================
//  QUERIES
// ============================================================

/// @desc Is (x, y) inside sector _s (even-odd over all its loops, so holes work)?
function world_in_sector(_w, _s, _px, _py)
{
    var _rs = _w.sec[_s];
    if (_px < _rs.x0 || _px > _rs.x1 || _py < _rs.y0 || _py > _rs.y1)
    {
        return false;
    }
    var _in = false;
    for (var _l = 0; _l < array_length(_rs.loops); _l++)
    {
        if (tri_point_in(_rs.loops[_l], _px, _py))
        {
            _in = !_in;
        }
    }
    return _in;
}

/// @desc Index of the sector under (x, y) for something with its feet at _pz,
/// or -1. Where sectors overlap (room over room) it is the highest floor at
/// most a step above the feet.
function world_sector_at(_w, _px, _py, _pz)
{
    var _best = -1;
    var _best_f = -infinity;
    var _low = -1;
    var _low_f = infinity;
    for (var _s = 0; _s < _w.nsec; _s++)
    {
        if (!world_in_sector(_w, _s, _px, _py))
        {
            continue;
        }
        var _f = world_floor_at(_w, _s, _px, _py);
        if (_f <= _pz + PL_STEP + 1 && _f > _best_f)
        {
            _best = _s;
            _best_f = _f;
        }
        if (_f < _low_f)
        {
            _low = _s;
            _low_f = _f;
        }
    }
    if (_best >= 0)
    {
        return _best;
    }
    return _low;
}

/// @desc Floor / ceiling height of sector _s at (x, y), slopes and movers included.
function world_floor_at(_w, _s, _px, _py)
{
    var _rs = _w.sec[_s];
    return _rs.fp[0] * _px + _rs.fp[1] * _py + _rs.fp[2] + _rs.foff;
}

function world_ceil_at(_w, _s, _px, _py)
{
    var _rs = _w.sec[_s];
    return _rs.cp[0] * _px + _rs.cp[1] * _py + _rs.cp[2] + _rs.coff;
}

/// @desc Edges whose blockmap cells touch the box (each edge once).
function world_edges_near(_w, _x0, _y0, _x1, _y1)
{
    _w.stamp_id += 1;
    var _id = _w.stamp_id;
    var _out = [];
    var _cx0 = clamp(floor((_x0 - _w.bm_x0) / WORLD_BLOCK), 0, _w.bm_cols - 1);
    var _cy0 = clamp(floor((_y0 - _w.bm_y0) / WORLD_BLOCK), 0, _w.bm_rows - 1);
    var _cx1 = clamp(floor((_x1 - _w.bm_x0) / WORLD_BLOCK), 0, _w.bm_cols - 1);
    var _cy1 = clamp(floor((_y1 - _w.bm_y0) / WORLD_BLOCK), 0, _w.bm_rows - 1);
    for (var _cy = _cy0; _cy <= _cy1; _cy++)
    {
        for (var _cx = _cx0; _cx <= _cx1; _cx++)
        {
            var _cell = _w.bm_cells[_cy * _w.bm_cols + _cx];
            for (var _i = 0; _i < array_length(_cell); _i++)
            {
                var _e = _cell[_i];
                if (_w.stamp[_e] != _id)
                {
                    _w.stamp[_e] = _id;
                    array_push(_out, _e);
                }
            }
        }
    }
    return _out;
}

/// @desc Parameter t (0..1) along a -> b where it meets segment c -> d, or -1.
function world_seg_hit(_ax, _ay, _bx, _by, _cx, _cy, _dx, _dy)
{
    var _rx = _bx - _ax;
    var _ry = _by - _ay;
    var _sx = _dx - _cx;
    var _sy = _dy - _cy;
    var _den = _rx * _sy - _ry * _sx;
    if (abs(_den) < 0.000001)
    {
        return -1;
    }
    var _t = ((_cx - _ax) * _sy - (_cy - _ay) * _sx) / _den;
    var _u = ((_cx - _ax) * _ry - (_cy - _ay) * _rx) / _den;
    if (_t < 0 || _t > 1 || _u < 0 || _u > 1)
    {
        return -1;
    }
    return _t;
}

/// @desc Which side of edge _e point (x, y) is on: 0 front (right of v0 -> v1), 1 back.
function world_edge_side(_w, _e, _px, _py)
{
    var _ed = _w.edges[_e];
    var _a = _w.verts[_ed.v0];
    var _b = _w.verts[_ed.v1];
    if (tri_orient(_a[0], _a[1], _b[0], _b[1], _px, _py) >= 0)
    {
        return 0;
    }
    return 1;
}

/// @desc Open height range of two-sided edge _e at (x, y): [bottom, top].
function world_opening(_w, _e, _px, _py)
{
    var _ed = _w.edges[_e];
    var _bot = max(world_floor_at(_w, _ed.front, _px, _py), world_floor_at(_w, _ed.back, _px, _py));
    var _top = min(world_ceil_at(_w, _ed.front, _px, _py), world_ceil_at(_w, _ed.back, _px, _py));
    return [_bot, _top];
}

/// @desc Does a circle of radius _r at (x, y) overlap sector _s?
function world_circle_in_sector(_w, _s, _px, _py, _r)
{
    if (world_in_sector(_w, _s, _px, _py))
    {
        return true;
    }
    var _hs = _w.sec[_s].halfs;
    for (var _i = 0; _i < array_length(_hs); _i++)
    {
        var _ed = _w.edges[_hs[_i].e];
        var _a = _w.verts[_ed.v0];
        var _b = _w.verts[_ed.v1];
        var _dx = _b[0] - _a[0];
        var _dy = _b[1] - _a[1];
        var _l2 = max(_dx * _dx + _dy * _dy, 0.0001);
        var _t = clamp(((_px - _a[0]) * _dx + (_py - _a[1]) * _dy) / _l2, 0, 1);
        if (point_distance(_px, _py, _a[0] + _dx * _t, _a[1] + _dy * _t) < _r)
        {
            return true;
        }
    }
    return false;
}
