/// scr_tex
/// Textures are index images: an array of w * h Pepto indices (0..15) or
/// PEPTO_CLEAR (-1, transparent), row-major. They become tiny GameMaker sprites
/// made with sprite_create_from_surface, so each is on its own texture page and
/// gpu_set_texrepeat can tile it across a wall.
///
/// Limits (the engine's only art rules):
///  - at most TEX_MAX x TEX_MAX (16 x 16) pixels;
///  - world textures (walls, floors) must be a power of two on each side.
///
/// global.TEX is a struct: name -> { name, w, h, spr, tex, idx }.

#macro TEX_MAX 16

/// World units covered by one repeat of a 16 px texture (so 1 texel = 4 units).
#macro TEX_WORLD 64

function tex_init()
{
    global.TEX = {};
    global.TEX_NAMES = [];
}

function tex_is_pow2(_n)
{
    return (_n == 1 || _n == 2 || _n == 4 || _n == 8 || _n == 16);
}

/// @desc Make (or replace) texture _name from an index image. Returns true when
/// it was accepted. _world true requires power-of-two sides (texture repeat).
function tex_create(_name, _w, _h, _idx, _world)
{
    if (_w < 1 || _h < 1 || _w > TEX_MAX || _h > TEX_MAX)
    {
        show_debug_message("tex_create: '" + _name + "' is " + string(_w) + "x" + string(_h) + " - textures are at most 16x16");
        return false;
    }
    if (_world && !(tex_is_pow2(_w) && tex_is_pow2(_h)))
    {
        show_debug_message("tex_create: world texture '" + _name + "' must be 1/2/4/8/16 on each side");
        return false;
    }
    if (!is_array(_idx) || array_length(_idx) != _w * _h)
    {
        show_debug_message("tex_create: '" + _name + "' index image has the wrong length");
        return false;
    }

    var _buf = buffer_create(_w * _h * 4, buffer_fixed, 1);
    for (var _i = 0; _i < _w * _h; _i++)
    {
        var _k = _idx[_i];
        if (_k < 0 || _k >= PEPTO_COUNT)
        {
            buffer_write(_buf, buffer_u32, 0);
        }
        else
        {
            var _c = global.PEPTO_RGB[_k];
            buffer_write(_buf, buffer_u8, _c[0]);
            buffer_write(_buf, buffer_u8, _c[1]);
            buffer_write(_buf, buffer_u8, _c[2]);
            buffer_write(_buf, buffer_u8, 255);
        }
    }

    var _surf = surface_create(_w, _h);
    buffer_set_surface(_buf, _surf, 0);
    var _spr = sprite_create_from_surface(_surf, 0, 0, _w, _h, false, false, 0, 0);
    surface_free(_surf);
    buffer_delete(_buf);

    var _old = global.TEX[$ _name];
    if (!is_undefined(_old))
    {
        sprite_delete(_old.spr);
    }
    else
    {
        array_push(global.TEX_NAMES, _name);
    }

    global.TEX[$ _name] = {
        name: _name,
        w: _w,
        h: _h,
        spr: _spr,
        tex: sprite_get_texture(_spr, 0),
        idx: _idx
    };
    return true;
}

/// @desc Texture struct by name, or undefined.
function tex_get(_name)
{
    return global.TEX[$ _name];
}

function tex_free_all()
{
    for (var _i = 0; _i < array_length(global.TEX_NAMES); _i++)
    {
        var _t = global.TEX[$ global.TEX_NAMES[_i]];
        if (!is_undefined(_t))
        {
            sprite_delete(_t.spr);
        }
    }
    global.TEX = {};
    global.TEX_NAMES = [];
}

// ============================================================
//  PROCEDURAL TEST SET (until the texture editor exists)
// ============================================================

/// @desc Small deterministic hash 0..1 for texel noise.
function tex_hash(_i, _seed)
{
    var _v = ((_i + 1) * 1103515245 + _seed * 12345) mod 2147483647;
    _v = (_v * 16807 + 11) mod 2147483647;
    return (_v mod 1000) / 1000;
}

/// @desc 16x16 bricks: mortar _m, brick _b, highlight _h, shade _s.
function tex_gen_bricks(_m, _b, _h, _s, _seed)
{
    var _a = array_create(256, _b);
    for (var _ty = 0; _ty < 16; _ty++)
    {
        var _row = _ty div 4;
        var _off = 0;
        if (_row mod 2 == 1)
        {
            _off = 4;
        }
        for (var _tx = 0; _tx < 16; _tx++)
        {
            var _i = _ty * 16 + _tx;
            var _k = _b;
            if (_ty mod 4 == 3 || (_tx + _off) mod 8 == 7)
            {
                _k = _m;
            }
            else if (_ty mod 4 == 0)
            {
                _k = _h;
            }
            else if (tex_hash(_i, _seed) < 0.18)
            {
                _k = _s;
            }
            _a[_i] = _k;
        }
    }
    return _a;
}

/// @desc 16x16 floor slabs: 8x8 tiles with a bevel.
function tex_gen_slabs(_base, _light, _dark, _seed)
{
    var _a = array_create(256, _base);
    for (var _ty = 0; _ty < 16; _ty++)
    {
        for (var _tx = 0; _tx < 16; _tx++)
        {
            var _i = _ty * 16 + _tx;
            var _k = _base;
            if (_tx mod 8 == 0 || _ty mod 8 == 0)
            {
                _k = _light;
            }
            else if (_tx mod 8 == 7 || _ty mod 8 == 7)
            {
                _k = _dark;
            }
            else if (tex_hash(_i, _seed) < 0.12)
            {
                _k = _dark;
            }
            _a[_i] = _k;
        }
    }
    return _a;
}

/// @desc 16x16 tech panel: frame, rivets, a lit stripe.
function tex_gen_panel(_frame, _fill, _rivet, _stripe)
{
    var _a = array_create(256, _fill);
    for (var _ty = 0; _ty < 16; _ty++)
    {
        for (var _tx = 0; _tx < 16; _tx++)
        {
            var _i = _ty * 16 + _tx;
            var _k = _fill;
            if (_tx == 0 || _ty == 0 || _tx == 15 || _ty == 15)
            {
                _k = _frame;
            }
            else if ((_tx == 2 || _tx == 13) && (_ty == 2 || _ty == 13))
            {
                _k = _rivet;
            }
            else if (_ty >= 6 && _ty <= 8 && _tx >= 3 && _tx <= 12)
            {
                _k = _stripe;
            }
            _a[_i] = _k;
        }
    }
    return _a;
}

/// @desc 16x16 rough rock / ceiling noise from three colours.
function tex_gen_noise(_a0, _a1, _a2, _seed)
{
    var _a = array_create(256, _a0);
    for (var _i = 0; _i < 256; _i++)
    {
        var _h = tex_hash(_i, _seed);
        if (_h < 0.25)
        {
            _a[_i] = _a1;
        }
        else if (_h < 0.33)
        {
            _a[_i] = _a2;
        }
    }
    return _a;
}

function tex_make_test_set()
{
    tex_create("BRICK", 16, 16, tex_gen_bricks(PEPTO_DARK_GREY, PEPTO_RED, PEPTO_LIGHT_RED, PEPTO_BROWN, 3), true);
    tex_create("STONE", 16, 16, tex_gen_bricks(PEPTO_DARK_GREY, PEPTO_MID_GREY, PEPTO_LIGHT_GREY, PEPTO_DARK_GREY, 7), true);
    tex_create("SLAB", 16, 16, tex_gen_slabs(PEPTO_MID_GREY, PEPTO_LIGHT_GREY, PEPTO_DARK_GREY, 5), true);
    tex_create("MOSS", 16, 16, tex_gen_slabs(PEPTO_GREEN, PEPTO_LIGHT_GREEN, PEPTO_BROWN, 9), true);
    tex_create("PANEL", 16, 16, tex_gen_panel(PEPTO_DARK_GREY, PEPTO_BLUE, PEPTO_LIGHT_GREY, PEPTO_CYAN), true);
    tex_create("ROCK", 16, 16, tex_gen_noise(PEPTO_BROWN, PEPTO_ORANGE, PEPTO_BLACK, 11), true);
    tex_create("CEIL", 16, 16, tex_gen_noise(PEPTO_DARK_GREY, PEPTO_BLUE, PEPTO_BLACK, 13), true);
    tex_create("STEP", 16, 16, tex_gen_panel(PEPTO_ORANGE, PEPTO_BROWN, PEPTO_YELLOW, PEPTO_YELLOW), true);
}
