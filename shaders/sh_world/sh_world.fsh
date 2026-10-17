// sh_world - texture x sector light x diminishing light (Doom style).
// Output is full colour; sh_pepto_lock snaps it to the 16 Pepto colours later.
varying vec2 v_vTexcoord;
varying vec4 v_vColour;
varying float v_vDist;

uniform float u_falloff;    // distance (world units) where the light is darkest

void main()
{
    vec4 tex = texture2D(gm_BaseTexture, v_vTexcoord);
    if (tex.a < 0.5)
    {
        discard;
    }
    float light = v_vColour.r;
    // Bright sectors keep some light far away, dark ones fade to black sooner
    float fade = clamp(1.0 - v_vDist / max(u_falloff, 1.0), 0.0, 1.0);
    float shade = light * mix(0.25, 1.0, fade);
    gl_FragColor = vec4(tex.rgb * shade, 1.0);
}
