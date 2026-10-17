// sh_crt - CRT monitor emulation as a single full-screen pass.
//
// Barrel curvature, radial chromatic aberration, phosphor bloom, scanlines,
// an RGB aperture mask, vignette, mains flicker and a small colour grade.
// Written from scratch for PIX3LL3D; every stage is driven by a uniform so the
// POST FX panel can dial each one to zero independently.

varying vec2 v_vTexcoord;
varying vec4 v_vColour;

uniform vec2  u_res;         // surface size in pixels
uniform vec2  u_texel;       // 1.0 / u_res
uniform float u_time;        // seconds, for flicker
uniform float u_curve;       // barrel distortion
uniform float u_scan;        // scanline depth
uniform float u_scan_lines;  // number of virtual scanlines down the screen
uniform float u_mask;        // aperture grille strength
uniform float u_glow;        // phosphor bloom
uniform float u_chroma;      // chromatic aberration
uniform float u_vignette;    // corner falloff
uniform float u_bright;
uniform float u_contrast;
uniform float u_sat;
uniform float u_flicker;

const float TAU = 6.28318530718;

// Push the sampling coordinate outward with distance from the centre.
vec2 curve_uv(vec2 uv)
{
    vec2 c = uv * 2.0 - 1.0;
    float r2 = dot(c, c);
    c *= 1.0 + u_curve * r2 * 0.25;
    return c * 0.5 + 0.5;
}

// Cheap ring blur used as the phosphor bloom source.
vec3 glow_sample(vec2 uv)
{
    vec3 sum = vec3(0.0);
    for (int i = 0; i < 8; i++)
    {
        float a = float(i) * (TAU / 8.0);
        vec2 off = vec2(cos(a), sin(a)) * u_texel * 2.5;
        sum += texture2D(gm_BaseTexture, uv + off).rgb;
    }
    return sum * 0.125;
}

void main()
{
    vec2 uv = curve_uv(v_vTexcoord);

    // Outside the tube face is the bezel: solid black.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
    {
        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    vec2 dir = uv - vec2(0.5);

    // --- Chromatic aberration: red splays out, blue pulls in ---
    float ca = u_chroma * 0.004;
    vec3 col;
    col.r = texture2D(gm_BaseTexture, uv + dir * ca).r;
    col.g = texture2D(gm_BaseTexture, uv).g;
    col.b = texture2D(gm_BaseTexture, uv - dir * ca).b;

    // --- Phosphor bloom: only the bright parts spill ---
    if (u_glow > 0.0)
    {
        vec3 g = glow_sample(uv);
        col += max(g - vec3(0.25), vec3(0.0)) * u_glow;
    }

    // --- Scanlines ---
    float lines = max(u_scan_lines, 1.0);
    float sl = 0.55 + 0.45 * cos(uv.y * lines * TAU);
    col *= mix(1.0, sl, clamp(u_scan, 0.0, 1.0));

    // --- Aperture grille: three-pixel RGB triad ---
    float px = floor(mod(v_vTexcoord.x * u_res.x, 3.0));
    vec3 grille = vec3(0.72);
    grille.r += step(px, 0.5) * 0.28;
    grille.g += step(0.5, px) * step(px, 1.5) * 0.28;
    grille.b += step(1.5, px) * 0.28;
    col *= mix(vec3(1.0), grille, clamp(u_mask, 0.0, 1.0));

    // --- Vignette ---
    float vig = 1.0 - u_vignette * dot(dir, dir) * 1.6;
    col *= clamp(vig, 0.0, 1.0);

    // --- Mains flicker ---
    col *= 1.0 - u_flicker * 0.05 * (0.5 + 0.5 * sin(u_time * 47.0));

    // --- Grade: contrast, brightness, saturation ---
    col = (col - vec3(0.5)) * u_contrast + vec3(0.5);
    col *= u_bright;
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(lum), col, u_sat);

    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
