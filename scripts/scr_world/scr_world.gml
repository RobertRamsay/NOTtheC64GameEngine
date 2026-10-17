/// scr_world
/// Sector + portal levels (Doom / Build style), drawn as true 3D.
///
/// level = { name, sectors: [ sector ], start: { x, y, angle } }
/// sector = {
///     pts:   [x0, y0, x1, y1, ...]   polygon (convex for now), one winding for all
///                                    sectors; edge i runs pt i -> pt i+1
///     floor, ceil                    heights, +Z up
///     ftex, ctex                     floor / ceiling texture names
///     light                          0..1
///     edges: [ { tex, portal } ]     portal = neighbour sector index or -1
///     ltex                           texture for step / lintel faces on portal edges
/// }
///
/// world_bake() turns a level into one frozen vertex buffer per texture.

function world_init()
{
    vertex_format_begin();
    vertex_format_add_position_3d();
    vertex_format_add_colour();
    vertex_format_add_texcoord();
    global.WORLD_VFORMAT = vertex_format_end();
}

/// @desc A sector with every edge a solid wall of texture _wtex.
function sector_make(_pts, _floor, _ceil, _ftex, _ctex, _wtex, _light)
{
    var _n = array_length(_pts) div 2;
    var _edges = array_create(_n, undefined);
    for (var _i = 0; _i < _n; _i++)
    {
        _edges[_i] = { tex: _wtex, portal: -1 };
    }
    return {
        pts: _pts,
        floor: _floor,
        ceil: _ceil,
        ftex: _ftex,
        ctex: _ctex,
        light: _light,
        edges: _edges,
        ltex: _wtex
    };
}

/// @desc Axis-aligned rectangle sector with extra split points so it can share
/// edges with neighbours. _splits_* are coordinates along each side (sorted).
function sector_rect(_x0, _y0, _x1, _y1, _splits_n, _splits_e, _splits_s, _splits_w, _floor, _ceil, _ftex, _ctex, _wtex, _light)
{
    // Clockwise on screen (Y down): north edge eastward, east edge southward,
    // south edge westward, west edge northward.
    var _p = [_x0, _y0];
    for (var _i = 0; _i < array_length(_splits_n); _i++)
    {
        array_push(_p, _splits_n[_i], _y0);
    }
    array_push(_p, _x1, _y0);
    for (var _i = 0; _i < array_length(_splits_e); _i++)
    {
        array_push(_p, _x1, _splits_e[_i]);
    }
    array_push(_p, _x1, _y1);
    for (var _i = array_length(_splits_s) - 1; _i >= 0; _i--)
    {
        array_push(_p, _splits_s[_i], _y1);
    }
    array_push(_p, _x0, _y1);
    for (var _i = array_length(_splits_w) - 1; _i >= 0; _i--)
    {
        array_push(_p, _x0, _splits_w[_i]);
    }
    return sector_make(_p, _floor, _ceil, _ftex, _ctex, _wtex, _light);
}

/// @desc Join every pair of edges that lie on top of each other into portals.
function world_auto_portals(_level)
{
    var _secs = _level.sectors;
    var _ns = array_length(_secs);
    for (var _a = 0; _a < _ns; _a++)
    {
        var _sa = _secs[_a];
        var _na = array_length(_sa.pts) div 2;
        for (var _i = 0; _i < _na; _i++)
        {
            var _ax0 = _sa.pts[_i * 2];
            var _ay0 = _sa.pts[_i * 2 + 1];
            var _ax1 = _sa.pts[((_i + 1) mod _na) * 2];
            var _ay1 = _sa.pts[((_i + 1) mod _na) * 2 + 1];
            for (var _b = 0; _b < _ns; _b++)
            {
                if (_b == _a)
                {
                    continue;
                }
                var _sb = _secs[_b];
                var _nb = array_length(_sb.pts) div 2;
                for (var _j = 0; _j < _nb; _j++)
                {
                    var _bx0 = _sb.pts[_j * 2];
                    var _by0 = _sb.pts[_j * 2 + 1];
                    var _bx1 = _sb.pts[((_j + 1) mod _nb) * 2];
                    var _by1 = _sb.pts[((_j + 1) mod _nb) * 2 + 1];
                    var _rev = (_ax0 == _bx1 && _ay0 == _by1 && _ax1 == _bx0 && _ay1 == _by0);
                    var _same = (_ax0 == _bx0 && _ay0 == _by0 && _ax1 == _bx1 && _ay1 == _by1);
                    if (_rev || _same)
                    {
                        _sa.edges[_i].portal = _b;
                    }
                }
            }
        }
    }
}

/// @desc The test level: a start room, a stepped corridor, a tall hall and a dark alcove.
function world_test_level()
{
    var _secs = [];

    // 0: start room
    array_push(_secs, sector_rect(0, 0, 512, 512, [], [192, 320], [], [], 0, 192, "SLAB", "CEIL", "BRICK", 0.95));

    // 1..4: corridor, each slice 16 units higher (stairs up to the hall)
    for (var _k = 0; _k < 4; _k++)
    {
        var _s = sector_rect(512 + _k * 64, 192, 576 + _k * 64, 320, [], [], [], [], _k * 16, 144 + _k * 16, "SLAB", "PANEL", "PANEL", 0.7 - _k * 0.05);
        _s.ltex = "STEP";
        array_push(_secs, _s);
    }

    // 5: the hall
    var _hall = sector_rect(768, 0, 1280, 640, [], [], [896, 1152], [192, 320], 64, 384, "MOSS", "CEIL", "STONE", 1.0);
    _hall.ltex = "STEP";
    array_push(_secs, _hall);

    // 6: dark alcove, one step up from the hall
    var _alc = sector_rect(896, 640, 1152, 896, [], [], [], [], 80, 208, "ROCK", "ROCK", "ROCK", 0.35);
    _alc.ltex = "STONE";
    array_push(_secs, _alc);

    var _level = {
        name: "TEST",
        sectors: _secs,
        start: { x: 96, y: 256, angle: 0 }
    };
    world_auto_portals(_level);
    return _level;
}

// ============================================================
//  BAKING
// ============================================================

/// @desc Get (or start) the vertex buffer batch for texture _name.
function world_batch(_batches, _name)
{
    var _b = _batches[$ _name];
    if (is_undefined(_b))
    {
        var _vb = vertex_create_buffer();
        vertex_begin(_vb, global.WORLD_VFORMAT);
        _b = { name: _name, vb: _vb, tris: 0 };
        _batches[$ _name] = _b;
    }
    return _b;
}

function world_vert(_vb, _wx, _wy, _wz, _shade, _u, _v)
{
    var _l = clamp(round(_shade * 255), 0, 255);
    vertex_position_3d(_vb, _wx, _wy, _wz);
    vertex_colour(_vb, make_colour_rgb(_l, _l, _l), 1);
    vertex_texcoord(_vb, _u, _v);
}

/// @desc A vertical quad from (x0,y0) to (x1,y1) between z _zb (bottom) and _zt (top).
function world_wall_quad(_b, _x0, _y0, _x1, _y1, _zb, _zt, _shade)
{
    if (_zt <= _zb)
    {
        return;
    }
    var _len = point_distance(_x0, _y0, _x1, _y1);
    var _u1 = _len / TEX_WORLD;
    var _vt = -_zt / TEX_WORLD;
    var _vb = -_zb / TEX_WORLD;
    var _buf = _b.vb;
    world_vert(_buf, _x0, _y0, _zt, _shade, 0, _vt);
    world_vert(_buf, _x1, _y1, _zt, _shade, _u1, _vt);
    world_vert(_buf, _x1, _y1, _zb, _shade, _u1, _vb);
    world_vert(_buf, _x0, _y0, _zt, _shade, 0, _vt);
    world_vert(_buf, _x1, _y1, _zb, _shade, _u1, _vb);
    world_vert(_buf, _x0, _y0, _zb, _shade, 0, _vb);
    _b.tris += 2;
}

/// @desc Fan-triangulated horizontal polygon at height _z (convex sectors).
function world_flat(_b, _pts, _z, _shade)
{
    var _n = array_length(_pts) div 2;
    var _buf = _b.vb;
    for (var _i = 1; _i < _n - 1; _i++)
    {
        var _ax = _pts[0];
        var _ay = _pts[1];
        var _bx = _pts[_i * 2];
        var _by = _pts[_i * 2 + 1];
        var _cx = _pts[(_i + 1) * 2];
        var _cy = _pts[(_i + 1) * 2 + 1];
        world_vert(_buf, _ax, _ay, _z, _shade, _ax / TEX_WORLD, _ay / TEX_WORLD);
        world_vert(_buf, _bx, _by, _z, _shade, _bx / TEX_WORLD, _by / TEX_WORLD);
        world_vert(_buf, _cx, _cy, _z, _shade, _cx / TEX_WORLD, _cy / TEX_WORLD);
        _b.tris += 1;
    }
}

/// @desc Bake _level into frozen vertex buffers. Returns { batches: [ {name, vb, tris} ], tris }.
function world_bake(_level)
{
    var _batches = {};
    var _secs = _level.sectors;

    for (var _s = 0; _s < array_length(_secs); _s++)
    {
        var _sec = _secs[_s];
        var _n = array_length(_sec.pts) div 2;

        world_flat(world_batch(_batches, _sec.ftex), _sec.pts, _sec.floor, _sec.light);
        world_flat(world_batch(_batches, _sec.ctex), _sec.pts, _sec.ceil, _sec.light * 0.85);

        for (var _i = 0; _i < _n; _i++)
        {
            var _x0 = _sec.pts[_i * 2];
            var _y0 = _sec.pts[_i * 2 + 1];
            var _x1 = _sec.pts[((_i + 1) mod _n) * 2];
            var _y1 = _sec.pts[((_i + 1) mod _n) * 2 + 1];
            var _e = _sec.edges[_i];

            // Doom's fake contrast: walls along X a little brighter than walls along Y
            var _len = max(point_distance(_x0, _y0, _x1, _y1), 1);
            var _shade = _sec.light * (0.8 + 0.2 * abs(_x1 - _x0) / _len);

            if (_e.portal < 0)
            {
                world_wall_quad(world_batch(_batches, _e.tex), _x0, _y0, _x1, _y1, _sec.floor, _sec.ceil, _shade);
            }
            else
            {
                var _nb = _secs[_e.portal];
                // Step face: neighbour floor is higher, seen from this sector
                if (_nb.floor > _sec.floor)
                {
                    world_wall_quad(world_batch(_batches, _sec.ltex), _x0, _y0, _x1, _y1, _sec.floor, min(_nb.floor, _sec.ceil), _shade);
                }
                // Lintel: neighbour ceiling is lower
                if (_nb.ceil < _sec.ceil)
                {
                    world_wall_quad(world_batch(_batches, _sec.ltex), _x0, _y0, _x1, _y1, max(_nb.ceil, _sec.floor), _sec.ceil, _shade);
                }
            }
        }
    }

    var _out = { batches: [], tris: 0 };
    var _names = struct_get_names(_batches);
    array_sort(_names, true);
    for (var _i = 0; _i < array_length(_names); _i++)
    {
        var _b = _batches[$ _names[_i]];
        vertex_end(_b.vb);
        if (_b.tris > 0)
        {
            vertex_freeze(_b.vb);
            array_push(_out.batches, _b);
            _out.tris += _b.tris;
        }
        else
        {
            vertex_delete_buffer(_b.vb);
        }
    }
    return _out;
}

function world_free(_baked)
{
    for (var _i = 0; _i < array_length(_baked.batches); _i++)
    {
        vertex_delete_buffer(_baked.batches[_i].vb);
    }
    _baked.batches = [];
    _baked.tris = 0;
}

/// @desc Submit every batch. Call with sh_world set.
function world_draw(_baked)
{
    for (var _i = 0; _i < array_length(_baked.batches); _i++)
    {
        var _b = _baked.batches[_i];
        var _t = tex_get(_b.name);
        if (is_undefined(_t))
        {
            continue;
        }
        vertex_submit(_b.vb, pr_trianglelist, _t.tex);
    }
}

// ============================================================
//  QUERIES
// ============================================================

/// @desc Point in polygon (crossing number; also right for concave polygons).
function world_point_in_poly(_pts, _px, _py)
{
    var _n = array_length(_pts) div 2;
    var _in = false;
    var _j = _n - 1;
    for (var _i = 0; _i < _n; _i++)
    {
        var _xi = _pts[_i * 2];
        var _yi = _pts[_i * 2 + 1];
        var _xj = _pts[_j * 2];
        var _yj = _pts[_j * 2 + 1];
        if (((_yi > _py) != (_yj > _py)) && (_px < (_xj - _xi) * (_py - _yi) / (_yj - _yi) + _xi))
        {
            _in = !_in;
        }
        _j = _i;
    }
    return _in;
}

/// @desc Index of the sector under (x, y), or -1.
function world_sector_at(_level, _px, _py)
{
    var _secs = _level.sectors;
    for (var _s = 0; _s < array_length(_secs); _s++)
    {
        if (world_point_in_poly(_secs[_s].pts, _px, _py))
        {
            return _s;
        }
    }
    return -1;
}
