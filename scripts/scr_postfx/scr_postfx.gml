/// scr_postfx
/// CRT parameters and shader uniforms for sh_crt (from PiX3LL3D POSTFX_system).
/// The slider panel will come across with the editor UI; for now F6 toggles it.
///
/// State on obj_engine (Create): fx, fx_u, fx_crt_on.

/// @desc A fresh parameter set, tuned for a 320 x 200 picture.
function postfx_defaults()
{
    return {
        crt_curve: 0.25,
        crt_scan: 0.35,
        crt_lines: RENDER_H,    // one dark gap per C64 raster line
        crt_mask: 0.15,
        crt_glow: 0.00,         // 8 extra texture fetches per pixel when above zero
        crt_chroma: 0.40,
        crt_vignette: 0.35,
        crt_bright: 1.10,
        crt_contrast: 1.04,
        crt_sat: 1.05,
        crt_flicker: 0.15
    };
}

/// @desc Cache every shader uniform handle once, at Create.
function postfx_uniforms()
{
    return {
        res:      shader_get_uniform(sh_crt, "u_res"),
        texel:    shader_get_uniform(sh_crt, "u_texel"),
        time:     shader_get_uniform(sh_crt, "u_time"),
        curve:    shader_get_uniform(sh_crt, "u_curve"),
        scan:     shader_get_uniform(sh_crt, "u_scan"),
        lines:    shader_get_uniform(sh_crt, "u_scan_lines"),
        mask:     shader_get_uniform(sh_crt, "u_mask"),
        glow:     shader_get_uniform(sh_crt, "u_glow"),
        chroma:   shader_get_uniform(sh_crt, "u_chroma"),
        vignette: shader_get_uniform(sh_crt, "u_vignette"),
        bright:   shader_get_uniform(sh_crt, "u_bright"),
        contrast: shader_get_uniform(sh_crt, "u_contrast"),
        sat:      shader_get_uniform(sh_crt, "u_sat"),
        flicker:  shader_get_uniform(sh_crt, "u_flicker")
    };
}

/// @desc Draw surface _surf at (_dx, _dy) size (_dw, _dh), through the CRT when it is on.
function postfx_present(_surf, _dx, _dy, _dw, _dh)
{
    var _old_filter = gpu_get_tex_filter();
    draw_set_colour(c_white);
    draw_set_alpha(1);

    if (fx_crt_on)
    {
        // Linear filtering, so the curvature resamples smoothly
        gpu_set_tex_filter(true);
        shader_set(sh_crt);
        shader_set_uniform_f(fx_u.res, _dw, _dh);
        shader_set_uniform_f(fx_u.texel, 1 / max(_dw, 1), 1 / max(_dh, 1));
        shader_set_uniform_f(fx_u.time, current_time / 1000);
        shader_set_uniform_f(fx_u.curve, fx.crt_curve);
        shader_set_uniform_f(fx_u.scan, fx.crt_scan);
        shader_set_uniform_f(fx_u.lines, fx.crt_lines);
        shader_set_uniform_f(fx_u.mask, fx.crt_mask);
        shader_set_uniform_f(fx_u.glow, fx.crt_glow);
        shader_set_uniform_f(fx_u.chroma, fx.crt_chroma);
        shader_set_uniform_f(fx_u.vignette, fx.crt_vignette);
        shader_set_uniform_f(fx_u.bright, fx.crt_bright);
        shader_set_uniform_f(fx_u.contrast, fx.crt_contrast);
        shader_set_uniform_f(fx_u.sat, fx.crt_sat);
        shader_set_uniform_f(fx_u.flicker, fx.crt_flicker);
        draw_surface_stretched(_surf, _dx, _dy, _dw, _dh);
        shader_reset();
    }
    else
    {
        gpu_set_tex_filter(false);
        draw_surface_stretched(_surf, _dx, _dy, _dw, _dh);
    }

    gpu_set_tex_filter(_old_filter);
}
