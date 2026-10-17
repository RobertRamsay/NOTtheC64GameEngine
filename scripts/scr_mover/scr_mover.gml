/// scr_mover
/// Sector specials that move (docs/CONTENT_TOOLS.md §A4) and the edge actions
/// that start them. Data only: everything comes from the level's edge actions.
///
/// Effects (action.effect) and their parameters:
///   door     ceiling up to the lowest neighbour ceiling - MV_DOOR_LIP.
///            mode "" (open, wait, close) | "open" (stay open) | "close".
///            Used again while open it closes; it reopens if it closes on the pawn.
///   lift     floor down to the lowest neighbour floor, waits, comes back up.
///   crusher  ceiling down to floor + MV_CRUSH_GAP and back up, until fired
///            again. It backs off when it reaches the pawn (no damage yet).
///   floor    floor to a height:   to "next_higher" | "next_lower" | "lowest" |
///   ceiling  ceiling to a height: "highest" | "set" (height) | "by" (height, the default)
///   speed (units per frame) and wait (frames) override the defaults when > 0 / >= 0.
///
/// Movers only change a sector's foff / coff (offsets from the rest height).
/// Each moving plane's travel is worked out at bake time (mover_bake_ranges) so
/// the geometry can be built for it; a mover never leaves that range.

#macro MV_DOOR_SPEED  3
#macro MV_DOOR_WAIT   150
#macro MV_DOOR_LIP    4
#macro MV_LIFT_SPEED  4
#macro MV_LIFT_WAIT   120
#macro MV_CRUSH_SPEED 1.5
#macro MV_CRUSH_GAP   8
#macro MV_PLANE_SPEED 2

// Mover phases
#macro MVP_GO   0
#macro MVP_WAIT 1
#macro MVP_BACK 2

/// @desc Sectors an edge's action works on: tag 0 = the edge's back sector.
function mover_targets(_w, _e)
{
    var _ed = _w.edges[_e];
    var _tag = _ed.action.tag;
    var _out = [];
    if (_tag == 0)
    {
        if (_ed.back >= 0)
        {
            array_push(_out, _ed.back);
        }
        return _out;
    }
    for (var _s = 0; _s < _w.nsec; _s++)
    {
        if (_w.sec[_s].tag == _tag)
        {
            array_push(_out, _s);
        }
    }
    return _out;
}

function mover_is_ceil(_effect)
{
    return (_effect == "door" || _effect == "crusher" || _effect == "ceiling");
}

function mover_is_effect(_effect)
{
    return (_effect == "door" || _effect == "lift" || _effect == "crusher" || _effect == "floor" || _effect == "ceiling");
}

/// @desc Current base height of a sector's floor or ceiling.
function mover_height(_w, _s, _ceil)
{
    var _rs = _w.sec[_s];
    if (_ceil)
    {
        return _rs.ceil + _rs.coff;
    }
    return _rs.floor + _rs.foff;
}

/// @desc A neighbour height relative to _cur: _which is "lowest", "highest",
/// "next_higher" or "next_lower". Falls back to _cur when there is none.
function mover_nb_height(_w, _s, _ceil, _which, _cur)
{
    var _nbs = _w.sec[_s].nbs;
    var _out = _cur;
    var _found = false;
    for (var _i = 0; _i < array_length(_nbs); _i++)
    {
        var _h = mover_height(_w, _nbs[_i], _ceil);
        if (_which == "lowest")
        {
            if (!_found || _h < _out)
            {
                _out = _h;
                _found = true;
            }
        }
        else if (_which == "highest")
        {
            if (!_found || _h > _out)
            {
                _out = _h;
                _found = true;
            }
        }
        else if (_which == "next_higher")
        {
            if (_h > _cur && (!_found || _h < _out))
            {
                _out = _h;
                _found = true;
            }
        }
        else if (_which == "next_lower")
        {
            if (_h < _cur && (!_found || _h > _out))
            {
                _out = _h;
                _found = true;
            }
        }
    }
    return _out;
}

/// @desc Where an effect sends its plane first, as a base height.
function mover_dest(_w, _s, _a)
{
    var _f = mover_height(_w, _s, false);
    var _c = mover_height(_w, _s, true);
    var _eff = _a.effect;
    if (_eff == "door")
    {
        if (_a.mode == "close")
        {
            return _f;
        }
        return max(_f, mover_nb_height(_w, _s, true, "lowest", _c + MV_DOOR_LIP) - MV_DOOR_LIP);
    }
    if (_eff == "lift")
    {
        return min(_f, mover_nb_height(_w, _s, false, "lowest", _f));
    }
    if (_eff == "crusher")
    {
        return _f + MV_CRUSH_GAP;
    }
    var _ceil = (_eff == "ceiling");
    var _cur = _f;
    if (_ceil)
    {
        _cur = _c;
    }
    var _to = _a.to;
    if (_to == "set")
    {
        return _a.height;
    }
    if (_to == "lowest" || _to == "highest" || _to == "next_higher" || _to == "next_lower")
    {
        return mover_nb_height(_w, _s, _ceil, _to, _cur);
    }
    return _cur + _a.height;
}

/// @desc Grow sector _s's floor or ceiling range to include offset _off.
function mover_extend(_rs, _ceil, _off)
{
    if (_ceil)
    {
        _rs.cmin = min(_rs.cmin, _off);
        _rs.cmax = max(_rs.cmax, _off);
    }
    else
    {
        _rs.fmin = min(_rs.fmin, _off);
        _rs.fmax = max(_rs.fmax, _off);
    }
}

/// @desc Work out how far every plane can travel, from the level's actions.
/// Called by world_bake before any geometry is built.
function mover_bake_ranges(_w)
{
    for (var _e = 0; _e < array_length(_w.edges); _e++)
    {
        var _ed = _w.edges[_e];
        if (_ed.front < 0 || _ed.action.trigger == "none" || !mover_is_effect(_ed.action.effect))
        {
            continue;
        }
        var _a = _ed.action;
        var _ceil = mover_is_ceil(_a.effect);
        var _tg = mover_targets(_w, _e);
        for (var _i = 0; _i < array_length(_tg); _i++)
        {
            var _rs = _w.sec[_tg[_i]];
            var _base = _rs.floor;
            if (_ceil)
            {
                _base = _rs.ceil;
            }
            mover_extend(_rs, _ceil, mover_dest(_w, _tg[_i], _a) - _base);
            if (_a.effect == "door")
            {
                // A door also closes down onto its floor
                mover_extend(_rs, true, _rs.floor - _rs.ceil);
            }
        }
    }
}

/// @desc Fire edge _e's action if its trigger is _trigger ("use", "walk",
/// "shoot"). Returns true when something started (or changed direction).
function action_fire(_w, _e, _trigger)
{
    var _ed = _w.edges[_e];
    var _a = _ed.action;
    if (_a.trigger != _trigger || _w.edge_used[_e])
    {
        return false;
    }
    var _tg = mover_targets(_w, _e);
    var _any = false;
    for (var _i = 0; _i < array_length(_tg); _i++)
    {
        if (mover_apply(_w, _tg[_i], _a))
        {
            _any = true;
        }
    }
    if (_any && !_a.repeat)
    {
        _w.edge_used[_e] = true;
    }
    var _note = "";
    if (!_any)
    {
        _note = " (busy)";
    }
    _w.last_event = _trigger + " edge " + string(_e) + ": " + _a.effect + _note;
    show_debug_message("ACTION " + _w.last_event);
    return _any;
}

function mover_new(_w, _s, _ceil, _kind, _dest, _speed, _wait)
{
    var _mv = {
        sector: _s,
        ceil: _ceil,
        kind: _kind,
        phase: MVP_GO,
        dest: _dest,
        speed: _speed,
        wait: _wait,
        timer: 0,
        open: 0,
        closed: 0,
        low: 0,
        mode: ""
    };
    if (_ceil)
    {
        _w.sec[_s].cmv = _mv;
    }
    else
    {
        _w.sec[_s].fmv = _mv;
    }
    array_push(_w.movers, _mv);
    return _mv;
}

function mover_remove(_w, _mv)
{
    if (_mv.ceil)
    {
        _w.sec[_mv.sector].cmv = undefined;
    }
    else
    {
        _w.sec[_mv.sector].fmv = undefined;
    }
    for (var _i = 0; _i < array_length(_w.movers); _i++)
    {
        if (_w.movers[_i] == _mv)
        {
            array_delete(_w.movers, _i, 1);
            return;
        }
    }
}

/// @desc Apply action _a to sector _s. Returns true when it did something.
function mover_apply(_w, _s, _a)
{
    var _rs = _w.sec[_s];
    var _eff = _a.effect;
    if (!mover_is_effect(_eff))
    {
        return false;
    }
    var _ceil = mover_is_ceil(_eff);
    var _speed = _a.speed;
    var _wait = _a.wait;

    if (_eff == "door")
    {
        if (_speed <= 0)
        {
            _speed = MV_DOOR_SPEED;
        }
        if (_wait < 0)
        {
            _wait = MV_DOOR_WAIT;
        }
        var _open = clamp(mover_dest(_w, _s, { effect: "door", mode: "open" }) - _rs.ceil, _rs.cmin, _rs.cmax);
        var _closed = clamp(_rs.floor + _rs.foff - _rs.ceil, _rs.cmin, _rs.cmax);
        var _mv = _rs.cmv;
        if (!is_undefined(_mv))
        {
            if (_mv.kind != "door")
            {
                return false;
            }
            if (_mv.phase == MVP_BACK)
            {
                _mv.phase = MVP_GO;
                _mv.dest = _mv.open;
            }
            else if (_a.mode != "open")
            {
                _mv.phase = MVP_BACK;
                _mv.dest = _mv.closed;
            }
            else
            {
                return false;
            }
            return true;
        }
        _mv = mover_new(_w, _s, true, "door", _open, _speed, _wait);
        _mv.open = _open;
        _mv.closed = _closed;
        _mv.mode = _a.mode;
        if (_a.mode == "close" || (_rs.coff >= _open - 0.5 && _a.mode != "open"))
        {
            _mv.phase = MVP_BACK;
            _mv.dest = _closed;
        }
        return true;
    }

    if (_eff == "crusher")
    {
        if (!is_undefined(_rs.cmv))
        {
            if (_rs.cmv.kind == "crusher")
            {
                mover_remove(_w, _rs.cmv);
                return true;
            }
            return false;
        }
        if (_speed <= 0)
        {
            _speed = MV_CRUSH_SPEED;
        }
        var _low = clamp(mover_dest(_w, _s, _a) - _rs.ceil, _rs.cmin, _rs.cmax);
        var _mv = mover_new(_w, _s, true, "crusher", _low, _speed, 0);
        _mv.low = _low;
        return true;
    }

    // Floor-ish movers: one per plane at a time
    if (_ceil)
    {
        if (!is_undefined(_rs.cmv))
        {
            return false;
        }
    }
    else if (!is_undefined(_rs.fmv))
    {
        return false;
    }

    if (_eff == "lift")
    {
        if (_speed <= 0)
        {
            _speed = MV_LIFT_SPEED;
        }
        if (_wait < 0)
        {
            _wait = MV_LIFT_WAIT;
        }
        var _low = clamp(mover_dest(_w, _s, _a) - _rs.floor, _rs.fmin, _rs.fmax);
        var _mv = mover_new(_w, _s, false, "lift", _low, _speed, _wait);
        _mv.low = _low;
        return true;
    }

    // floor / ceiling
    if (_speed <= 0)
    {
        _speed = MV_PLANE_SPEED;
    }
    var _base = _rs.floor;
    var _lo = _rs.fmin;
    var _hi = _rs.fmax;
    var _cur = _rs.foff;
    if (_ceil)
    {
        _base = _rs.ceil;
        _lo = _rs.cmin;
        _hi = _rs.cmax;
        _cur = _rs.coff;
    }
    var _dest = clamp(mover_dest(_w, _s, _a) - _base, _lo, _hi);
    if (_dest == _cur)
    {
        return false;
    }
    mover_new(_w, _s, _ceil, _eff, _dest, _speed, 0);
    return true;
}

/// @desc Move _cur towards _dest by at most _step.
function mover_approach(_cur, _dest, _step)
{
    if (_cur < _dest)
    {
        return min(_cur + _step, _dest);
    }
    return max(_cur - _step, _dest);
}

/// @desc Run every active mover for one frame. The pawn (feet at _pz) stops
/// ceilings and floors that would squash it when _solid is true.
function world_tick(_w, _px, _py, _pz, _solid)
{
    for (var _i = array_length(_w.movers) - 1; _i >= 0; _i--)
    {
        var _mv = _w.movers[_i];
        if (mover_tick(_w, _mv, _px, _py, _pz, _solid))
        {
            mover_remove(_w, _mv);
        }
    }
}

/// @desc One frame of one mover. Returns true when it has finished.
function mover_tick(_w, _mv, _px, _py, _pz, _solid)
{
    var _rs = _w.sec[_mv.sector];
    if (_mv.phase == MVP_WAIT)
    {
        _mv.timer -= 1;
        if (_mv.timer <= 0)
        {
            _mv.phase = MVP_BACK;
            if (_mv.kind == "door")
            {
                _mv.dest = _mv.closed;
            }
            else
            {
                _mv.dest = 0;
            }
        }
        return false;
    }

    var _cur = _rs.foff;
    if (_mv.ceil)
    {
        _cur = _rs.coff;
    }
    var _next = mover_approach(_cur, _mv.dest, _mv.speed);

    // Would this squash the pawn?
    if (_solid && _next != _cur && world_circle_in_sector(_w, _mv.sector, _px, _py, PL_RADIUS))
    {
        if (_mv.ceil && _next < _cur)
        {
            var _top = _rs.cp[0] * _px + _rs.cp[1] * _py + _rs.cp[2] + _next;
            if (_top < _pz + PL_HEAD)
            {
                if (_mv.kind == "door")
                {
                    _mv.phase = MVP_GO;
                    _mv.dest = _mv.open;
                }
                else if (_mv.kind == "crusher")
                {
                    // No damage until the enemies milestone: back off
                    _mv.phase = MVP_BACK;
                    _mv.dest = 0;
                }
                return false;
            }
        }
        if (!_mv.ceil && _next > _cur)
        {
            var _bot = _rs.fp[0] * _px + _rs.fp[1] * _py + _rs.fp[2] + _next;
            var _ceil_z = world_ceil_at(_w, _mv.sector, _px, _py);
            if (_bot + PL_HEAD > _ceil_z)
            {
                if (_mv.kind == "lift")
                {
                    _mv.phase = MVP_GO;
                    _mv.dest = _mv.low;
                }
                return false;
            }
        }
    }

    if (_mv.ceil)
    {
        _rs.coff = _next;
    }
    else
    {
        _rs.foff = _next;
    }
    if (_next != _mv.dest)
    {
        return false;
    }

    // Arrived
    if (_mv.kind == "door")
    {
        if (_mv.phase == MVP_GO)
        {
            if (_mv.mode == "open")
            {
                return true;
            }
            _mv.phase = MVP_WAIT;
            _mv.timer = _mv.wait;
            return false;
        }
        return true;
    }
    if (_mv.kind == "lift")
    {
        if (_mv.phase == MVP_GO)
        {
            _mv.phase = MVP_WAIT;
            _mv.timer = _mv.wait;
            return false;
        }
        return true;
    }
    if (_mv.kind == "crusher")
    {
        if (_mv.phase == MVP_GO)
        {
            _mv.phase = MVP_BACK;
            _mv.dest = 0;
        }
        else
        {
            _mv.phase = MVP_GO;
            _mv.dest = _mv.low;
        }
        return false;
    }
    return true;
}
