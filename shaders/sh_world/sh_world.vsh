// sh_world - world geometry. Passes the texcoord, the baked light (vertex
// colour) and the distance from the eye for diminishing light.
attribute vec3 in_Position;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;

varying vec2 v_vTexcoord;
varying vec4 v_vColour;
varying float v_vDist;

void main()
{
    vec4 pos = vec4(in_Position, 1.0);
    gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * pos;
    v_vDist = length((gm_Matrices[MATRIX_WORLD_VIEW] * pos).xyz);
    v_vColour = in_Colour;
    v_vTexcoord = in_TextureCoord;
}
