/// scr_postfx
/// CRT parameters and shader uniforms for sh_crt (from PiX3LL3D POSTFX_system).
/// The Options menu (scr_menu) edits them through postfx_slider_defs; F6 toggles
/// the CRT. They are saved with the other settings (scr_settings).
///
/// State on obj_engine (Create): fx, fx_u, fx_crt_on.

#macro SCAN_OFF 0
#macro SCAN_PROGRESSIVE 1
#macro SCAN_INTERLACED 2

/// @desc A fresh parameter set, tuned for a 320 x 200 picture.
function postfx_defaults()
{
    return {
        crt_curve: 0.25,
        crt_scan_mode: SCAN_PROGRESSIVE,
        crt_scan: 0.35,
        crt_lines: RENDER_H,    // one dark gap per C64 raster line
        crt_blur: 0.50,         // composite smear in game pixels
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

/// @desc Slider rows for the Options menu. step 0 is continuous.
function postfx_slider_defs()
{
    return [
        { key: "crt_scan",     label: "Scanline depth", lo: 0.00, hi: 1.00, step: 0 },
        { key: "crt_blur",     label: "Blur",           lo: 0.00, hi: 2.00, step: 0 },
        { key: "crt_curve",    label: "Curvature",      lo: 0.00, hi: 2.00, step: 0 },
        { key: "crt_mask",     label: "Aperture mask",  lo: 0.00, hi: 1.00, step: 0 },
        { key: "crt_chroma",   label: "Colour fringe",  lo: 0.00, hi: 3.00, step: 0 },
        { key: "crt_glow",     label: "Glow",           lo: 0.00, hi: 2.00, step: 0 },
        { key: "crt_vignette", label: "Vignette",       lo: 0.00, hi: 1.50, step: 0 },
        { key: "crt_flicker",  label: "Flicker",        lo: 0.00, hi: 1.00, step: 0 },
        { key: "crt_bright",   label: "Brightness",     lo: 0.50, hi: 2.00, step: 0 },
        { key: "crt_contrast", label: "Contrast",       lo: 0.50, hi: 2.00, step: 0 },
        { key: "crt_sat",      label: "Saturation",     lo: 0.00, hi: 2.00, step: 0 }
    ];
}

/// @desc Cache every shader uniform handle once, at Create.
function postfx_uniforms()
{
    return {
        res:       shader_get_uniform(sh_crt, "u_res"),
        texel:     shader_get_uniform(sh_crt, "u_texel"),
        time:      shader_get_uniform(sh_crt, "u_time"),
        curve:     shader_get_uniform(sh_crt, "u_curve"),
        scan:      shader_get_uniform(sh_crt, "u_scan"),
        lines:     shader_get_uniform(sh_crt, "u_scan_lines"),
        mask:      shader_get_uniform(sh_crt, "u_mask"),
        glow:      shader_get_uniform(sh_crt, "u_glow"),
        chroma:    shader_get_uniform(sh_crt, "u_chroma"),
        vignette:  shader_get_uniform(sh_crt, "u_vignette"),
        bright:    shader_get_uniform(sh_crt, "u_bright"),
        contrast:  shader_get_uniform(sh_crt, "u_contrast"),
        sat:       shader_get_uniform(sh_crt, "u_sat"),
        flicker:   shader_get_uniform(sh_crt, "u_flicker"),
        src_texel: shader_get_uniform(sh_crt, "u_src_texel"),
        blur:      shader_get_uniform(sh_crt, "u_blur"),
        interlace: shader_get_uniform(sh_crt, "u_interlace"),
        field:     shader_get_uniform(sh_crt, "u_field")
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
        var _scan = fx.crt_scan;
        if (fx.crt_scan_mode == SCAN_OFF)
        {
            _scan = 0;
        }
        var _interlace = 0;
        if (fx.crt_scan_mode == SCAN_INTERLACED)
        {
            _interlace = 1;
        }

        // Linear filtering, so the curvature resamples smoothly
        gpu_set_tex_filter(true);
        shader_set(sh_crt);
        shader_set_uniform_f(fx_u.res, _dw, _dh);
        shader_set_uniform_f(fx_u.texel, 1 / max(_dw, 1), 1 / max(_dh, 1));
        shader_set_uniform_f(fx_u.time, current_time / 1000);
        shader_set_uniform_f(fx_u.curve, fx.crt_curve);
        shader_set_uniform_f(fx_u.scan, _scan);
        shader_set_uniform_f(fx_u.lines, fx.crt_lines);
        shader_set_uniform_f(fx_u.mask, fx.crt_mask);
        shader_set_uniform_f(fx_u.glow, fx.crt_glow);
        shader_set_uniform_f(fx_u.chroma, fx.crt_chroma);
        shader_set_uniform_f(fx_u.vignette, fx.crt_vignette);
        shader_set_uniform_f(fx_u.bright, fx.crt_bright);
        shader_set_uniform_f(fx_u.contrast, fx.crt_contrast);
        shader_set_uniform_f(fx_u.sat, fx.crt_sat);
        shader_set_uniform_f(fx_u.flicker, fx.crt_flicker);
        shader_set_uniform_f(fx_u.src_texel, 1 / surface_get_width(_surf), 1 / surface_get_height(_surf));
        shader_set_uniform_f(fx_u.blur, fx.crt_blur);
        shader_set_uniform_f(fx_u.interlace, _interlace);
        shader_set_uniform_f(fx_u.field, frame_no mod 2);
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
