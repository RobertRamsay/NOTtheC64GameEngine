/// scr_level
/// Level data, JSON v1 (docs/CONTENT_TOOLS.md §A6). Engine core: the Player
/// reads this, the Level Editor writes it.
///
/// level = {
///     version: 1, name,
///     settings: { music, sky, fog, gravity, par, next, secret_next },
///     vertices: [ [x, y], ... ],
///     sectors:  [ { floor, ceil, ftex, ctex, light, tag, special,
///                   fslope: { edge, rise }, cslope: { edge, rise } } ],
///     edges:    [ { v0, v1, front, back, flags, action, sides: [ side, side ] } ],
///     things:   [ { type, x, y, z, angle, tag, flags } ]
/// }
///
/// Edges are stored once (Doom linedefs). The front sector is on the right of
/// v0 -> v1 as seen on the plan (Y down), the back sector on the left; back -1
/// is a solid one-sided wall. sides[0] faces the front sector, sides[1] the back:
///     side = { upper, middle, lower, ox, oy, sx, sy }
/// Textures are names ("" = none). Offsets are world units, scale 1 = one
/// repeat per TEX_WORLD units. A two-sided middle texture is see-through (grates).
///
/// A slope is a hinge edge of the sector plus a rise: the plane is at the
/// sector's floor (or ceil) height along the hinge, and `rise` higher at the
/// sector's point furthest from it. edge -1 = flat.
///
/// action = { trigger, repeat, effect, tag, mode, to, height, speed, wait }
///     trigger: "none" | "use" | "walk" | "shoot"
///     effect:  "door" | "lift" | "crusher" | "floor" | "ceiling"
///     tag 0 acts on the edge's back sector (Doom's door lines), otherwise on
///     every sector with that tag. See scr_mover for mode / to / height.
///
/// Missing keys get defaults on load, so old files keep loading.

#macro LEVEL_VERSION 1

// Edge flags
#macro EDGE_BLOCK         1     // blocks the player and monsters even when two-sided
#macro EDGE_BLOCK_MONSTER 2     // blocks monsters only (enemies milestone)
#macro EDGE_BLOCK_SOUND   4     // stops noise flooding (enemies milestone)
#macro EDGE_SECRET        8     // drawn as a solid wall on the automap (later)

// Thing flags (skill levels)
#macro THING_EASY   1
#macro THING_NORMAL 2
#macro THING_HARD   4
#macro THING_ALL    7

// ============================================================
//  DEFAULTS
// ============================================================

function level_settings_default()
{
    return {
        music: "",
        sky: "",
        fog: RENDER_FALLOFF,
        gravity: PL_GRAVITY,
        par: 0,
        next: "",
        secret_next: ""
    };
}

function level_slope_default()
{
    return { edge: -1, rise: 0 };
}

function level_sector_default()
{
    return {
        floor: 0,
        ceil: 128,
        ftex: "SLAB",
        ctex: "CEIL",
        light: 1,
        tag: 0,
        special: "",
        fslope: level_slope_default(),
        cslope: level_slope_default()
    };
}

function level_side_default()
{
    return { upper: "", middle: "", lower: "", ox: 0, oy: 0, sx: 1, sy: 1 };
}

function level_action_default()
{
    return {
        trigger: "none",
        repeat: false,
        effect: "",
        tag: 0,
        mode: "",
        to: "",
        height: 0,
        speed: 0,
        wait: -1
    };
}

function level_edge_default()
{
    return {
        v0: 0,
        v1: 0,
        front: -1,
        back: -1,
        flags: 0,
        action: level_action_default(),
        sides: [level_side_default(), level_side_default()]
    };
}

function level_thing_default()
{
    return { type: "player_start", x: 0, y: 0, z: 0, angle: 0, tag: 0, flags: THING_ALL };
}

function level_new(_name)
{
    return {
        version: LEVEL_VERSION,
        name: _name,
        settings: level_settings_default(),
        vertices: [],
        sectors: [],
        edges: [],
        things: []
    };
}

// ============================================================
//  NORMALISE (fill defaults, drop broken records)
// ============================================================

/// @desc Copy every key of _def from _src when it has the same kind of value.
/// Nested structs are filled the same way.
function level_fill(_def, _src)
{
    if (!is_struct(_src))
    {
        return _def;
    }
    var _keys = struct_get_names(_def);
    for (var _i = 0; _i < array_length(_keys); _i++)
    {
        var _k = _keys[_i];
        var _d = _def[$ _k];
        var _v = _src[$ _k];
        if (is_undefined(_v))
        {
            continue;
        }
        if (is_struct(_d))
        {
            _def[$ _k] = level_fill(_d, _v);
        }
        else if (is_string(_d))
        {
            if (is_string(_v))
            {
                _def[$ _k] = _v;
            }
        }
        else if (is_bool(_d))
        {
            if (is_bool(_v) || is_numeric(_v))
            {
                _def[$ _k] = bool(_v);
            }
        }
        else if (is_numeric(_d))
        {
            if (is_numeric(_v))
            {
                _def[$ _k] = real(_v);
            }
        }
    }
    return _def;
}

/// @desc A clean v1 level from parsed JSON (or any struct of the same shape).
function level_normalize(_src)
{
    var _name = "UNTITLED";
    if (is_struct(_src) && is_string(_src[$ "name"]))
    {
        _name = _src[$ "name"];
    }
    var _lv = level_new(_name);
    if (!is_struct(_src))
    {
        return _lv;
    }
    _lv.settings = level_fill(level_settings_default(), _src[$ "settings"]);

    var _verts = _src[$ "vertices"];
    if (is_array(_verts))
    {
        for (var _i = 0; _i < array_length(_verts); _i++)
        {
            var _v = _verts[_i];
            if (is_array(_v) && array_length(_v) >= 2)
            {
                array_push(_lv.vertices, [real(_v[0]), real(_v[1])]);
            }
            else
            {
                array_push(_lv.vertices, [0, 0]);
            }
        }
    }
    var _nv = array_length(_lv.vertices);

    var _secs = _src[$ "sectors"];
    if (is_array(_secs))
    {
        for (var _i = 0; _i < array_length(_secs); _i++)
        {
            array_push(_lv.sectors, level_fill(level_sector_default(), _secs[_i]));
        }
    }
    var _ns = array_length(_lv.sectors);

    var _edges = _src[$ "edges"];
    if (is_array(_edges))
    {
        for (var _i = 0; _i < array_length(_edges); _i++)
        {
            var _es = _edges[_i];
            var _e = level_fill(level_edge_default(), _es);
            if (is_struct(_es) && is_array(_es[$ "sides"]))
            {
                var _sd = _es[$ "sides"];
                for (var _k = 0; _k < 2 && _k < array_length(_sd); _k++)
                {
                    _e.sides[_k] = level_fill(level_side_default(), _sd[_k]);
                }
            }
            if (_e.v0 < 0 || _e.v0 >= _nv || _e.v1 < 0 || _e.v1 >= _nv || _e.v0 == _e.v1 || _e.front < 0 || _e.front >= _ns)
            {
                // Kept (slopes refer to edges by index) but ignored by the bake
                show_debug_message("level_normalize: edge " + string(_i) + " is broken, ignored");
                _e.front = -1;
                _e.back = -1;
            }
            if (_e.back >= _ns)
            {
                _e.back = -1;
            }
            array_push(_lv.edges, _e);
        }
    }

    var _things = _src[$ "things"];
    if (is_array(_things))
    {
        for (var _i = 0; _i < array_length(_things); _i++)
        {
            array_push(_lv.things, level_fill(level_thing_default(), _things[_i]));
        }
    }
    return _lv;
}

// ============================================================
//  LOAD / SAVE
// ============================================================

/// @desc Load a level JSON file. Returns a v1 level, or undefined if the file
/// is missing or not JSON.
function level_load(_path)
{
    if (!file_exists(_path))
    {
        show_debug_message("level_load: no file " + _path);
        return undefined;
    }
    var _buf = buffer_load(_path);
    if (_buf < 0)
    {
        return undefined;
    }
    var _txt = buffer_read(_buf, buffer_string);
    buffer_delete(_buf);
    var _data = undefined;
    try
    {
        _data = json_parse(_txt);
    }
    catch (_err)
    {
        show_debug_message("level_load: " + _path + " is not valid JSON");
        return undefined;
    }
    if (!is_struct(_data))
    {
        return undefined;
    }
    var _ver = _data[$ "version"];
    if (is_numeric(_ver) && _ver > LEVEL_VERSION)
    {
        show_debug_message("level_load: " + _path + " is version " + string(_ver) + ", newer than this engine (" + string(LEVEL_VERSION) + ")");
    }
    return level_normalize(_data);
}

/// @desc A number as JSON text: integers plain, others with up to 6 decimals.
function level_json_number(_v)
{
    if (frac(_v) == 0)
    {
        return string(int64(_v));
    }
    var _s = string_format(_v, 0, 6);
    while (string_char_at(_s, string_length(_s)) == "0")
    {
        _s = string_delete(_s, string_length(_s), 1);
    }
    if (string_char_at(_s, string_length(_s)) == ".")
    {
        _s = string_delete(_s, string_length(_s), 1);
    }
    return _s;
}

function level_json_string(_s)
{
    _s = string_replace_all(_s, "\\", "\\\\");
    _s = string_replace_all(_s, "\"", "\\\"");
    _s = string_replace_all(_s, "\n", "\\n");
    return "\"" + _s + "\"";
}

/// @desc Any value as one line of JSON. Struct keys are written in _order first
/// (when given), then the rest sorted, so files diff cleanly.
function level_json_value(_v)
{
    if (is_bool(_v))
    {
        if (_v)
        {
            return "true";
        }
        return "false";
    }
    if (is_string(_v))
    {
        return level_json_string(_v);
    }
    if (is_numeric(_v))
    {
        return level_json_number(_v);
    }
    if (is_array(_v))
    {
        var _s = "[";
        for (var _i = 0; _i < array_length(_v); _i++)
        {
            if (_i > 0)
            {
                _s += ", ";
            }
            _s += level_json_value(_v[_i]);
        }
        return _s + "]";
    }
    if (is_struct(_v))
    {
        var _keys = level_json_key_order(_v);
        var _s = "{ ";
        for (var _i = 0; _i < array_length(_keys); _i++)
        {
            if (_i > 0)
            {
                _s += ", ";
            }
            _s += level_json_string(_keys[_i]) + ": " + level_json_value(_v[$ _keys[_i]]);
        }
        return _s + " }";
    }
    return "null";
}

/// @desc Keys of a level record in a fixed, readable order.
function level_json_key_order(_st)
{
    var _pref = ["version", "name", "type", "v0", "v1", "front", "back", "flags", "x", "y", "z", "angle",
        "floor", "ceil", "ftex", "ctex", "light", "trigger", "repeat", "effect", "tag", "edge", "rise",
        "upper", "middle", "lower"];
    var _names = struct_get_names(_st);
    array_sort(_names, true);
    var _out = [];
    for (var _i = 0; _i < array_length(_pref); _i++)
    {
        if (!is_undefined(_st[$ _pref[_i]]))
        {
            array_push(_out, _pref[_i]);
        }
    }
    for (var _i = 0; _i < array_length(_names); _i++)
    {
        var _n = _names[_i];
        var _known = false;
        for (var _k = 0; _k < array_length(_pref); _k++)
        {
            if (_pref[_k] == _n)
            {
                _known = true;
                break;
            }
        }
        if (!_known)
        {
            array_push(_out, _n);
        }
    }
    return _out;
}

/// @desc A top-level array, one record per line.
function level_json_list(_name, _arr, _last)
{
    var _s = "  " + level_json_string(_name) + ": [";
    if (array_length(_arr) == 0)
    {
        _s += "]";
    }
    else
    {
        _s += "\n";
        for (var _i = 0; _i < array_length(_arr); _i++)
        {
            _s += "    " + level_json_value(_arr[_i]);
            if (_i < array_length(_arr) - 1)
            {
                _s += ",";
            }
            _s += "\n";
        }
        _s += "  ]";
    }
    if (!_last)
    {
        _s += ",";
    }
    return _s + "\n";
}

/// @desc The level as human-readable JSON text.
function level_to_json(_lv)
{
    var _s = "{\n";
    _s += "  \"version\": " + string(LEVEL_VERSION) + ",\n";
    _s += "  \"name\": " + level_json_string(_lv.name) + ",\n";
    _s += "  \"settings\": " + level_json_value(_lv.settings) + ",\n";
    _s += level_json_list("vertices", _lv.vertices, false);
    _s += level_json_list("sectors", _lv.sectors, false);
    _s += level_json_list("edges", _lv.edges, false);
    _s += level_json_list("things", _lv.things, true);
    _s += "}\n";
    return _s;
}

/// @desc Write a level to a JSON file. Returns true on success.
function level_save(_lv, _path)
{
    var _txt = level_to_json(_lv);
    var _buf = buffer_create(string_byte_length(_txt) + 1, buffer_grow, 1);
    buffer_write(_buf, buffer_text, _txt);
    var _ok = true;
    try
    {
        buffer_save(_buf, _path);
    }
    catch (_err)
    {
        _ok = false;
    }
    buffer_delete(_buf);
    if (_ok)
    {
        show_debug_message("level_save: " + _path + " (" + string(array_length(_lv.sectors)) + " sectors, " + string(array_length(_lv.edges)) + " edges)");
    }
    else
    {
        show_debug_message("level_save: could not write " + _path);
    }
    return _ok;
}

// ============================================================
//  BUILDER - make levels from polygons in code (test levels, prefabs).
//  The Level Editor has its own drawing tools; this is the engine's minimum.
// ============================================================

function lb_begin(_name)
{
    return { level: level_new(_name), vkey: {}, ekey: {}, props: [] };
}

function lb_vertex(_b, _px, _py)
{
    var _k = string(round(_px * 16)) + "," + string(round(_py * 16));
    var _i = _b.vkey[$ _k];
    if (is_undefined(_i))
    {
        _i = array_length(_b.level.vertices);
        array_push(_b.level.vertices, [_px, _py]);
        _b.vkey[$ _k] = _i;
    }
    return _i;
}

/// @desc Add a sector. _props may set any sector key plus wall (middle texture
/// of its solid walls) and step (lower / upper texture of its portal walls).
/// _pts is clockwise on screen. An edge drawn the other way round by an earlier
/// sector becomes a portal between the two.
function lb_sector(_b, _pts, _props)
{
    var _sec = level_fill(level_sector_default(), _props);
    var _s = array_length(_b.level.sectors);
    array_push(_b.level.sectors, _sec);
    var _wall = "BRICK";
    if (is_string(_props[$ "wall"]))
    {
        _wall = _props[$ "wall"];
    }
    var _step = _wall;
    if (is_string(_props[$ "step"]))
    {
        _step = _props[$ "step"];
    }
    array_push(_b.props, { wall: _wall, step: _step });
    lb_loop(_b, _s, _pts, false);
    return _s;
}

/// @desc Add a loop of edges to sector _s. A hole (pillar) is given clockwise
/// like any shape and reversed here, so the sector stays on the right.
function lb_loop(_b, _s, _pts, _hole)
{
    var _n = array_length(_pts) div 2;
    var _vi = array_create(_n, 0);
    for (var _i = 0; _i < _n; _i++)
    {
        var _j = _i;
        if (_hole)
        {
            _j = _n - 1 - _i;
        }
        _vi[_i] = lb_vertex(_b, _pts[_j * 2], _pts[_j * 2 + 1]);
    }
    var _pr = _b.props[_s];
    for (var _i = 0; _i < _n; _i++)
    {
        var _va = _vi[_i];
        var _vb = _vi[(_i + 1) mod _n];
        var _rev = _b.ekey[$ string(_vb) + ">" + string(_va)];
        if (!is_undefined(_rev) && _b.level.edges[_rev].back < 0)
        {
            // Shared edge: it becomes a portal
            var _e = _b.level.edges[_rev];
            _e.back = _s;
            _e.sides[0].middle = "";
            _e.sides[1].lower = _pr.step;
            _e.sides[1].upper = _pr.step;
            continue;
        }
        var _e = level_edge_default();
        _e.v0 = _va;
        _e.v1 = _vb;
        _e.front = _s;
        _e.sides[0].middle = _pr.wall;
        _e.sides[0].lower = _pr.step;
        _e.sides[0].upper = _pr.step;
        _b.ekey[$ string(_va) + ">" + string(_vb)] = array_length(_b.level.edges);
        array_push(_b.level.edges, _e);
    }
}

/// @desc Axis-aligned rectangle points (clockwise on screen) with extra split
/// points along each side so it can share edges with neighbours.
function lb_rect(_x0, _y0, _x1, _y1, _splits_n, _splits_e, _splits_s, _splits_w)
{
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
    return _p;
}

/// @desc Index of the edge between two points (either direction), or -1.
function lb_edge(_b, _x0, _y0, _x1, _y1)
{
    var _va = lb_vertex(_b, _x0, _y0);
    var _vb = lb_vertex(_b, _x1, _y1);
    var _e = _b.ekey[$ string(_va) + ">" + string(_vb)];
    if (is_undefined(_e))
    {
        _e = _b.ekey[$ string(_vb) + ">" + string(_va)];
    }
    if (is_undefined(_e))
    {
        show_debug_message("lb_edge: no edge " + string(_x0) + "," + string(_y0) + " - " + string(_x1) + "," + string(_y1));
        return -1;
    }
    return _e;
}

/// @desc Turn edge _e round so that sector _s is its back (for tag-0 actions).
function lb_make_back(_b, _e, _s)
{
    var _ed = _b.level.edges[_e];
    if (_ed.back == _s || _ed.front != _s)
    {
        return;
    }
    var _v = _ed.v0;
    _ed.v0 = _ed.v1;
    _ed.v1 = _v;
    _ed.front = _ed.back;
    _ed.back = _s;
    var _sd = _ed.sides[0];
    _ed.sides[0] = _ed.sides[1];
    _ed.sides[1] = _sd;
}

/// @desc The side of edge _e that faces sector _s.
function lb_side(_b, _e, _s)
{
    var _ed = _b.level.edges[_e];
    if (_ed.back == _s)
    {
        return _ed.sides[1];
    }
    return _ed.sides[0];
}

/// @desc Give edge _e an action (struct with any action keys).
function lb_action(_b, _e, _act)
{
    _b.level.edges[_e].action = level_fill(level_action_default(), _act);
}

// ============================================================
//  TEST LEVEL
// ============================================================

/// @desc The test level, as v1 data: a start room with a pillar, a stepped
/// corridor to a tall hall with a shootable platform, a lift up to a dark
/// ledge, a door to a concave room with a grate window and a ramp up to a
/// crusher. Saved to datafiles/levels/test.json (build.ps1 -SaveLevel).
function world_test_level()
{
    var _b = lb_begin("TEST");

    // 0: start room, with a pillar (a hole in the sector)
    var _start = lb_sector(_b, lb_rect(0, 0, 512, 512, [], [192, 320], [192, 320], []),
        { floor: 0, ceil: 192, ftex: "SLAB", ctex: "CEIL", light: 0.95, wall: "BRICK" });
    _b.props[_start].wall = "STONE";
    lb_loop(_b, _start, lb_rect(224, 144, 288, 208, [], [], [], []), true);

    // 1..4: corridor, each slice 16 units higher (stairs up to the hall)
    for (var _k = 0; _k < 4; _k++)
    {
        lb_sector(_b, lb_rect(512 + _k * 64, 192, 576 + _k * 64, 320, [], [], [], []),
            { floor: _k * 16, ceil: 144 + _k * 16, ftex: "SLAB", ctex: "PANEL", light: 0.7 - _k * 0.05, wall: "PANEL", step: "STEP" });
    }

    // 5: the hall, with a square hole for the platform and a target on the east wall
    var _hall = lb_sector(_b, lb_rect(768, 0, 1280, 640, [], [288, 352], [896, 1152], [192, 320]),
        { floor: 64, ceil: 384, ftex: "MOSS", ctex: "CEIL", light: 1.0, wall: "STONE", step: "STEP" });
    lb_loop(_b, _hall, lb_rect(992, 288, 1056, 352, [], [], [], []), true);

    // 6: platform in the hall, raised by shooting the target (tag 1, once)
    lb_sector(_b, lb_rect(992, 288, 1056, 352, [], [], [], []),
        { floor: 64, ceil: 384, ftex: "STEP", ctex: "CEIL", light: 1.0, tag: 1, wall: "STEP", step: "STEP" });
    var _tgt = lb_edge(_b, 1280, 288, 1280, 352);
    lb_side(_b, _tgt, _hall).middle = "TARGET";
    lb_action(_b, _tgt, { trigger: "shoot", repeat: false, effect: "floor", to: "by", height: 64, tag: 1 });

    // 7: lift between the hall and the ledge (rests up, lowers to the hall floor)
    var _lift = lb_sector(_b, lb_rect(896, 640, 1152, 704, [], [], [], []),
        { floor: 192, ceil: 320, ftex: "STEP", ctex: "ROCK", light: 0.6, wall: "ROCK", step: "STONE" });
    // 8: dark ledge behind it
    var _ledge = lb_sector(_b, lb_rect(896, 704, 1152, 896, [], [], [], []),
        { floor: 192, ceil: 320, ftex: "ROCK", ctex: "ROCK", light: 0.35, wall: "ROCK", step: "STONE" });
    var _e = lb_edge(_b, 896, 640, 1152, 640);
    lb_make_back(_b, _e, _lift);
    lb_action(_b, _e, { trigger: "use", repeat: true, effect: "lift" });
    _e = lb_edge(_b, 896, 704, 1152, 704);
    lb_make_back(_b, _e, _lift);
    lb_action(_b, _e, { trigger: "walk", repeat: true, effect: "lift" });

    // 9: door south of the start room (rests closed)
    var _door = lb_sector(_b, lb_rect(192, 512, 320, 528, [], [], [], []),
        { floor: 0, ceil: 0, ftex: "SLAB", ctex: "STEP", light: 0.8, wall: "STEP", step: "DOOR" });

    // 10: concave L-shaped room, with splits for the grate window and the ramp
    var _lroom = lb_sector(_b, [64, 528, 192, 528, 320, 528, 448, 528, 448, 600, 448, 696, 448, 768,
        256, 768, 256, 960, 64, 960, 64, 928, 64, 800],
        { floor: 0, ceil: 192, ftex: "SLAB", ctex: "PANEL", light: 0.8, wall: "PANEL", step: "PANEL" });
    _e = lb_edge(_b, 192, 512, 320, 512);
    lb_make_back(_b, _e, _door);
    lb_side(_b, _e, _start).upper = "DOOR";
    lb_action(_b, _e, { trigger: "use", repeat: true, effect: "door" });
    _e = lb_edge(_b, 192, 528, 320, 528);
    lb_make_back(_b, _e, _door);
    lb_side(_b, _e, _lroom).upper = "DOOR";
    lb_action(_b, _e, { trigger: "use", repeat: true, effect: "door" });

    // 11: dark closet seen through a grate (a see-through, blocking middle texture)
    lb_sector(_b, lb_rect(448, 600, 544, 696, [], [], [], []),
        { floor: 32, ceil: 128, ftex: "ROCK", ctex: "ROCK", light: 0.45, wall: "BRICK", step: "PANEL" });
    _e = lb_edge(_b, 448, 600, 448, 696);
    lb_side(_b, _e, _lroom).middle = "GRATE";
    _b.level.edges[_e].flags = EDGE_BLOCK;

    // 12: ramp west of the L room: floor sloped from 0 at its east edge to 64
    var _ramp = lb_sector(_b, lb_rect(-192, 800, 64, 928, [], [], [], []),
        { floor: 0, ceil: 192, ftex: "MOSS", ctex: "CEIL", light: 0.75, wall: "STONE", step: "STONE" });
    var _hinge = lb_edge(_b, 64, 800, 64, 928);
    _b.level.sectors[_ramp].fslope = { edge: _hinge, rise: 64 };
    // Walking onto (or off) the ramp toggles the crusher at its top
    lb_action(_b, _hinge, { trigger: "walk", repeat: true, effect: "crusher", tag: 2 });

    // 13: crusher at the top of the ramp (tag 2)
    lb_sector(_b, lb_rect(-256, 800, -192, 928, [], [], [], []),
        { floor: 64, ceil: 192, ftex: "SLAB", ctex: "STEP", light: 0.7, tag: 2, wall: "STONE", step: "STEP" });

    var _pl = level_thing_default();
    _pl.x = 96;
    _pl.y = 256;
    array_push(_b.level.things, _pl);
    return _b.level;
}
