/// scr_pepto
/// The 16 Pepto C64 colours (Philip "Pepto" Timmermann's measured VIC-II palette,
/// values as in C64 Dev Machine scr_c64_pepto_colour and BKGDesigner shd_mosaic).
/// This is the ONLY palette the game image may use: sh_pepto_lock snaps every
/// pixel of rt_world to one of these.

#macro PEPTO_COUNT 16

#macro PEPTO_BLACK       0
#macro PEPTO_WHITE       1
#macro PEPTO_RED         2
#macro PEPTO_CYAN        3
#macro PEPTO_PURPLE      4
#macro PEPTO_GREEN       5
#macro PEPTO_BLUE        6
#macro PEPTO_YELLOW      7
#macro PEPTO_ORANGE      8
#macro PEPTO_BROWN       9
#macro PEPTO_LIGHT_RED   10
#macro PEPTO_DARK_GREY   11
#macro PEPTO_MID_GREY    12
#macro PEPTO_LIGHT_GREEN 13
#macro PEPTO_LIGHT_BLUE  14
#macro PEPTO_LIGHT_GREY  15

/// Index used in texture index images for a transparent pixel.
#macro PEPTO_CLEAR -1

/// @desc The palette as [r, g, b] (0..255) per index.
function pepto_rgb_table()
{
    return [
        [0, 0, 0],          // 0 Black
        [255, 255, 255],    // 1 White
        [104, 55, 43],      // 2 Red
        [112, 164, 178],    // 3 Cyan
        [111, 61, 134],     // 4 Purple
        [88, 141, 67],      // 5 Green
        [53, 40, 121],      // 6 Blue
        [184, 199, 111],    // 7 Yellow
        [111, 79, 37],      // 8 Orange
        [67, 57, 0],        // 9 Brown
        [154, 103, 89],     // 10 Light Red
        [68, 68, 68],       // 11 Dark Grey
        [108, 108, 108],    // 12 Mid Grey
        [154, 210, 132],    // 13 Light Green
        [108, 94, 181],     // 14 Light Blue
        [149, 149, 149]     // 15 Light Grey
    ];
}

function pepto_names()
{
    return [
        "Black", "White", "Red", "Cyan", "Purple", "Green", "Blue", "Yellow",
        "Orange", "Brown", "Light Red", "Dark Grey", "Mid Grey", "Light Green", "Light Blue", "Light Grey"
    ];
}

/// @desc Build the global tables once at start-up (obj_engine Create).
function pepto_init()
{
    global.PEPTO_RGB = pepto_rgb_table();
    global.PEPTO_NAMES = pepto_names();
    global.PEPTO_COL = array_create(PEPTO_COUNT, c_black);
    for (var _i = 0; _i < PEPTO_COUNT; _i++)
    {
        var _c = global.PEPTO_RGB[_i];
        global.PEPTO_COL[_i] = make_colour_rgb(_c[0], _c[1], _c[2]);
    }
}

/// @desc GameMaker colour of Pepto index _i (black when out of range).
function pepto_colour(_i)
{
    if (_i < 0 || _i >= PEPTO_COUNT)
    {
        return c_black;
    }
    return global.PEPTO_COL[_i];
}

/// @desc Nearest Pepto index to an RGB colour (0..255). RGB weighted 2:4:3,
/// the same metric sh_pepto_lock uses (luma weights snap dim greys to blue).
function pepto_nearest(_r, _g, _b)
{
    var _best = 0;
    var _best_d = infinity;
    for (var _i = 0; _i < PEPTO_COUNT; _i++)
    {
        var _c = global.PEPTO_RGB[_i];
        var _dr = _r - _c[0];
        var _dg = _g - _c[1];
        var _db = _b - _c[2];
        var _d = 2 * _dr * _dr + 4 * _dg * _dg + 3 * _db * _db;
        if (_d < _best_d)
        {
            _best_d = _d;
            _best = _i;
        }
    }
    return _best;
}

/// @desc True when the RGB colour (0..255) is exactly one of the 16.
function pepto_is_exact(_r, _g, _b)
{
    for (var _i = 0; _i < PEPTO_COUNT; _i++)
    {
        var _c = global.PEPTO_RGB[_i];
        if (_c[0] == _r && _c[1] == _g && _c[2] == _b)
        {
            return true;
        }
    }
    return false;
}

/// @desc The palette as 48 floats (r, g, b 0..1 per index) for shader_set_uniform_f_array.
function pepto_uniform_array()
{
    var _a = array_create(PEPTO_COUNT * 3, 0);
    for (var _i = 0; _i < PEPTO_COUNT; _i++)
    {
        var _c = global.PEPTO_RGB[_i];
        _a[_i * 3] = _c[0] / 255;
        _a[_i * 3 + 1] = _c[1] / 255;
        _a[_i * 3 + 2] = _c[2] / 255;
    }
    return _a;
}
