/// scr_tri
/// Triangulation of sector floors and ceilings: ear clipping, with holes
/// (a pillar inside a room) bridged into their outer loop first
/// (David Eberly, "Triangulation by Ear Clipping").
///
/// Loops are flat [x0, y0, x1, y1, ...] arrays. Sector loops keep the sector on
/// their right (clockwise on screen, Y down): outer loops have a positive
/// tri_area and holes a negative one.

/// @desc Twice the signed area of triangle a, b, c. Positive when c is to the
/// right of a -> b on screen (Y down).
function tri_orient(_ax, _ay, _bx, _by, _cx, _cy)
{
    return (_bx - _ax) * (_cy - _ay) - (_by - _ay) * (_cx - _ax);
}

/// @desc Signed area of a loop. Positive = clockwise on screen (an outer loop).
function tri_area(_pts)
{
    var _n = array_length(_pts) div 2;
    var _a = 0;
    for (var _i = 0; _i < _n; _i++)
    {
        var _j = (_i + 1) mod _n;
        _a += _pts[_i * 2] * _pts[_j * 2 + 1] - _pts[_j * 2] * _pts[_i * 2 + 1];
    }
    return _a * 0.5;
}

/// @desc Do the open segments a-b and c-d cross (touching ends do not count)?
function tri_seg_cross(_ax, _ay, _bx, _by, _cx, _cy, _dx, _dy)
{
    var _d1 = tri_orient(_cx, _cy, _dx, _dy, _ax, _ay);
    var _d2 = tri_orient(_cx, _cy, _dx, _dy, _bx, _by);
    var _d3 = tri_orient(_ax, _ay, _bx, _by, _cx, _cy);
    var _d4 = tri_orient(_ax, _ay, _bx, _by, _dx, _dy);
    if (((_d1 > 0 && _d2 < 0) || (_d1 < 0 && _d2 > 0)) && ((_d3 > 0 && _d4 < 0) || (_d3 < 0 && _d4 > 0)))
    {
        return true;
    }
    return false;
}

/// @desc Is p strictly inside segment a-b (on the line, between the ends)?
function tri_on_seg(_px, _py, _ax, _ay, _bx, _by)
{
    if (abs(tri_orient(_ax, _ay, _bx, _by, _px, _py)) > 0.0001)
    {
        return false;
    }
    if ((_px == _ax && _py == _ay) || (_px == _bx && _py == _by))
    {
        return false;
    }
    var _dot = (_px - _ax) * (_bx - _ax) + (_py - _ay) * (_by - _ay);
    var _len = (_bx - _ax) * (_bx - _ax) + (_by - _ay) * (_by - _ay);
    return (_dot > 0 && _dot < _len);
}

/// @desc Point in polygon (crossing number; right for concave polygons too).
function tri_point_in(_pts, _px, _py)
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

/// @desc Does segment m-v cross any edge of loop _pts (or pass through one of its vertices)?
function tri_bridge_blocked(_pts, _mx, _my, _vx, _vy)
{
    var _n = array_length(_pts) div 2;
    for (var _i = 0; _i < _n; _i++)
    {
        var _j = (_i + 1) mod _n;
        var _ax = _pts[_i * 2];
        var _ay = _pts[_i * 2 + 1];
        var _bx = _pts[_j * 2];
        var _by = _pts[_j * 2 + 1];
        if (tri_seg_cross(_mx, _my, _vx, _vy, _ax, _ay, _bx, _by))
        {
            return true;
        }
        if (tri_on_seg(_ax, _ay, _mx, _my, _vx, _vy))
        {
            return true;
        }
    }
    return false;
}

/// @desc Merge holes into outer loop _outer with zero-width bridges. Returns one
/// simple loop (with the bridge vertices doubled) ready for tri_earclip.
function tri_merge_holes(_outer, _holes)
{
    var _poly = [];
    array_copy(_poly, 0, _outer, 0, array_length(_outer));

    // Right-most hole first, so every later hole can bridge to the ones before it
    var _order = [];
    for (var _h = 0; _h < array_length(_holes); _h++)
    {
        var _hp = _holes[_h];
        var _best = 0;
        for (var _i = 1; _i < array_length(_hp) div 2; _i++)
        {
            if (_hp[_i * 2] > _hp[_best * 2])
            {
                _best = _i;
            }
        }
        array_push(_order, { pts: _hp, m: _best, mx: _hp[_best * 2], done: false });
    }
    array_sort(_order, function(_a, _b)
    {
        if (_a.mx > _b.mx)
        {
            return -1;
        }
        if (_a.mx < _b.mx)
        {
            return 1;
        }
        return 0;
    });

    for (var _h = 0; _h < array_length(_order); _h++)
    {
        var _ho = _order[_h];
        var _hp = _ho.pts;
        var _hn = array_length(_hp) div 2;
        var _mx = _hp[_ho.m * 2];
        var _my = _hp[_ho.m * 2 + 1];

        // Candidates: poly vertices at or right of M, nearest first
        var _cands = [];
        var _pn = array_length(_poly) div 2;
        for (var _i = 0; _i < _pn; _i++)
        {
            var _vx = _poly[_i * 2];
            var _vy = _poly[_i * 2 + 1];
            if (_vx >= _mx)
            {
                array_push(_cands, { i: _i, d: (_vx - _mx) * (_vx - _mx) + (_vy - _my) * (_vy - _my) });
            }
        }
        if (array_length(_cands) == 0)
        {
            for (var _i = 0; _i < _pn; _i++)
            {
                var _vx = _poly[_i * 2];
                var _vy = _poly[_i * 2 + 1];
                array_push(_cands, { i: _i, d: (_vx - _mx) * (_vx - _mx) + (_vy - _my) * (_vy - _my) });
            }
        }
        array_sort(_cands, function(_a, _b)
        {
            return _a.d - _b.d;
        });

        var _pick = _cands[0].i;
        for (var _c = 0; _c < array_length(_cands); _c++)
        {
            var _ci = _cands[_c].i;
            var _vx = _poly[_ci * 2];
            var _vy = _poly[_ci * 2 + 1];
            var _blocked = tri_bridge_blocked(_poly, _mx, _my, _vx, _vy);
            for (var _k = _h; _k < array_length(_order) && !_blocked; _k++)
            {
                if (tri_bridge_blocked(_order[_k].pts, _mx, _my, _vx, _vy))
                {
                    _blocked = true;
                }
            }
            if (!_blocked)
            {
                _pick = _ci;
                break;
            }
        }

        // poly[0.._pick], hole from M all the way round to M again, poly[_pick..]
        var _out = [];
        for (var _i = 0; _i <= _pick; _i++)
        {
            array_push(_out, _poly[_i * 2], _poly[_i * 2 + 1]);
        }
        for (var _k = 0; _k <= _hn; _k++)
        {
            var _j = (_ho.m + _k) mod _hn;
            array_push(_out, _hp[_j * 2], _hp[_j * 2 + 1]);
        }
        for (var _i = _pick; _i < _pn; _i++)
        {
            array_push(_out, _poly[_i * 2], _poly[_i * 2 + 1]);
        }
        _poly = _out;
    }
    return _poly;
}

/// @desc Ear-clip one simple loop with a positive tri_area. Returns a flat
/// triangle list [ax, ay, bx, by, cx, cy, ...].
function tri_earclip(_pts)
{
    var _tris = [];
    var _n = array_length(_pts) div 2;
    if (_n < 3)
    {
        return _tris;
    }
    var _idx = array_create(_n, 0);
    for (var _i = 0; _i < _n; _i++)
    {
        _idx[_i] = _i;
    }

    var _guard = _n * _n + 16;
    while (array_length(_idx) > 3 && _guard > 0)
    {
        _guard -= 1;
        var _cnt = array_length(_idx);
        var _found = -1;
        var _best = -1;
        var _best_o = -infinity;
        for (var _k = 0; _k < _cnt; _k++)
        {
            var _ia = _idx[(_k + _cnt - 1) mod _cnt];
            var _ib = _idx[_k];
            var _ic = _idx[(_k + 1) mod _cnt];
            var _ax = _pts[_ia * 2];
            var _ay = _pts[_ia * 2 + 1];
            var _bx = _pts[_ib * 2];
            var _by = _pts[_ib * 2 + 1];
            var _cx = _pts[_ic * 2];
            var _cy = _pts[_ic * 2 + 1];
            var _o = tri_orient(_ax, _ay, _bx, _by, _cx, _cy);
            if (_o > _best_o)
            {
                _best_o = _o;
                _best = _k;
            }
            if (_o <= 0)
            {
                continue;
            }
            // An ear holds no other vertex (points sitting on a, b or c are bridge twins)
            var _ear = true;
            for (var _q = 0; _q < _cnt && _ear; _q++)
            {
                var _iq = _idx[_q];
                if (_iq == _ia || _iq == _ib || _iq == _ic)
                {
                    continue;
                }
                var _px = _pts[_iq * 2];
                var _py = _pts[_iq * 2 + 1];
                if ((_px == _ax && _py == _ay) || (_px == _bx && _py == _by) || (_px == _cx && _py == _cy))
                {
                    continue;
                }
                if (tri_orient(_ax, _ay, _bx, _by, _px, _py) >= 0 && tri_orient(_bx, _by, _cx, _cy, _px, _py) >= 0 && tri_orient(_cx, _cy, _ax, _ay, _px, _py) >= 0)
                {
                    _ear = false;
                }
            }
            if (_ear)
            {
                _found = _k;
                array_push(_tris, _ax, _ay, _bx, _by, _cx, _cy);
                break;
            }
        }
        if (_found < 0)
        {
            // Bad or degenerate loop: clip the most convex corner so we always finish
            _found = _best;
            if (_best_o > 0)
            {
                var _ia = _idx[(_found + _cnt - 1) mod _cnt];
                var _ib = _idx[_found];
                var _ic = _idx[(_found + 1) mod _cnt];
                array_push(_tris, _pts[_ia * 2], _pts[_ia * 2 + 1], _pts[_ib * 2], _pts[_ib * 2 + 1], _pts[_ic * 2], _pts[_ic * 2 + 1]);
            }
        }
        array_delete(_idx, _found, 1);
    }
    if (array_length(_idx) == 3)
    {
        var _ia = _idx[0];
        var _ib = _idx[1];
        var _ic = _idx[2];
        if (tri_orient(_pts[_ia * 2], _pts[_ia * 2 + 1], _pts[_ib * 2], _pts[_ib * 2 + 1], _pts[_ic * 2], _pts[_ic * 2 + 1]) > 0)
        {
            array_push(_tris, _pts[_ia * 2], _pts[_ia * 2 + 1], _pts[_ib * 2], _pts[_ib * 2 + 1], _pts[_ic * 2], _pts[_ic * 2 + 1]);
        }
    }
    return _tris;
}

/// @desc Triangulate a sector from its loops (outer loops and holes, any order).
/// Each hole goes to the outer loop that contains it.
function tri_sector(_loops)
{
    var _outers = [];
    var _holes = [];
    for (var _i = 0; _i < array_length(_loops); _i++)
    {
        var _lp = _loops[_i];
        if (array_length(_lp) < 6)
        {
            continue;
        }
        if (tri_area(_lp) > 0)
        {
            array_push(_outers, { pts: _lp, holes: [] });
        }
        else
        {
            array_push(_holes, _lp);
        }
    }
    for (var _h = 0; _h < array_length(_holes); _h++)
    {
        var _hp = _holes[_h];
        // Test the middle of the hole's first edge: a hole may share a vertex with its outer loop
        var _tx = (_hp[0] + _hp[2]) * 0.5;
        var _ty = (_hp[1] + _hp[3]) * 0.5;
        for (var _o = 0; _o < array_length(_outers); _o++)
        {
            if (tri_point_in(_outers[_o].pts, _tx, _ty))
            {
                array_push(_outers[_o].holes, _hp);
                break;
            }
        }
    }
    var _tris = [];
    for (var _o = 0; _o < array_length(_outers); _o++)
    {
        var _poly = _outers[_o].pts;
        if (array_length(_outers[_o].holes) > 0)
        {
            _poly = tri_merge_holes(_poly, _outers[_o].holes);
        }
        var _t = tri_earclip(_poly);
        for (var _k = 0; _k < array_length(_t); _k++)
        {
            array_push(_tris, _t[_k]);
        }
    }
    return _tris;
}
