// sh_pepto_lock - the palette lock. Every output pixel is exactly one of the
// 16 Pepto colours. With dithering on, the pair of colours whose blend line
// passes closest to the true colour is found, and a 4x4 Bayer threshold picks
// between them, so gradients (lighting, fog) become C64-style ordered dither
// instead of hard bands. With dithering off it is the nearest colour.
//
// Distance metric: RGB weighted 2:4:3 (a cheap "redmean"), the same as
// pepto_nearest() in scr_pepto. Luma weights (0.3, 0.59, 0.11) are NOT used:
// they make dim greys snap to blue / brown.
varying vec2 v_vTexcoord;
varying vec4 v_vColour;

uniform vec3  u_pal[16];  // Pepto colours, 0..1
uniform float u_dither;   // 0 = nearest colour only, 1 = full ordered dither
uniform float u_on;       // 0 = bypass (debug view of the unlocked frame)

// Weight of a dither pair's own spread against how well it matches (see main)
// (0.05 already turns dim red into brown + red instead of black + red.)
#define PAIR_PENALTY 0.02

float bayer2(vec2 a)
{
    a = floor(a);
    return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float bayer4(vec2 a)
{
    return bayer2(a * 0.5) * 0.25 + bayer2(a);
}

void main()
{
    vec3 c = texture2D(gm_BaseTexture, v_vTexcoord).rgb;
    if (u_on < 0.5)
    {
        gl_FragColor = vec4(c, 1.0);
        return;
    }

    const vec3 W = vec3(2.0 / 9.0, 4.0 / 9.0, 3.0 / 9.0);

    // Nearest colour
    vec3 best = u_pal[0];
    float d_best = 1e9;
    for (int i = 0; i < 16; i++)
    {
        vec3 dd = c - u_pal[i];
        float d = dot(dd * dd, W);
        if (d < d_best)
        {
            d_best = d;
            best = u_pal[i];
        }
    }

    vec3 outc = best;
    if (u_dither > 0.0 && d_best > 0.0)
    {
        // Best pair (a, b) out of all 120: the segment a -> b that passes
        // closest to c, plus a small penalty on long segments so greys dither
        // with neighbouring greys, not with white. Doesn't have to include
        // the nearest colour: dim red is black + red, not brown + something.
        vec3 pa = best;
        vec3 pb = best;
        float t_pair = 0.0;
        float score_best = d_best;
        for (int i = 0; i < 16; i++)
        {
            for (int j = 0; j < 16; j++)
            {
                if (j > i)
                {
                    vec3 a = u_pal[i];
                    vec3 ab = u_pal[j] - a;
                    float len2 = dot(ab * ab, W);
                    float t = clamp(dot((c - a) * ab, W) / len2, 0.0, 1.0);
                    vec3 dd = c - (a + ab * t);
                    float score = dot(dd * dd, W) + PAIR_PENALTY * len2;
                    if (score < score_best)
                    {
                        score_best = score;
                        pa = a;
                        pb = u_pal[j];
                        t_pair = t;
                    }
                }
            }
        }
        float threshold = bayer4(gl_FragCoord.xy) + 1.0 / 32.0;
        outc = pa;
        if (t_pair * u_dither > threshold)
        {
            outc = pb;
        }
    }
    gl_FragColor = vec4(outc, 1.0);
}
