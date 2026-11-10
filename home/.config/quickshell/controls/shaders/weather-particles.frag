#version 440
#extension GL_GOOGLE_include_directive : enable
// Vent, étape 1 : simulation des particules (une par case de cellPx pixels de la carte), rendue dans une
// texture RGBA16F de cols × rows texels relue à l'image suivante (ShaderEffectSource récursive).
// Texel = (position dans la case 0..1, âge 0..1, durée de vie en s ; 0 = jamais née).
// Chaque case reprend la particule (la sienne d'abord, sinon une voisine) qui y arrive après advection ;
// sinon elle en fait naître une nouvelle à un endroit aléatoire : la densité reste constante.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float vw; float vh;
    float x0; float y0;
    float worldSize;
    float lon0; float lat0; float dlon; float dlat;
    float nlon; float nlat; float hours;
    float hourA; float hourB; float mixAB;
    float cols; float rows; float cellPx;
    float dt; float time;
};
layout(binding = 1) uniform sampler2D atlas;
layout(binding = 2) uniform sampler2D state;
#include "weather-common.glsl"
#include "weather-wind-common.glsl"

void main() {
    vec2 grid = vec2(cols, rows);
    vec2 c = floor(qt_TexCoord0 * grid);
    vec4 own = texture(state, (c + 0.5) / grid);
    vec4 res = vec4(0.0);
    bool found = false;
    for (int k = 0; k < 9; k++) {
        // la case elle-même d'abord (k = 0), puis ses 8 voisines
        int i = (k + 4) % 9;
        vec2 n = c + vec2(float(i % 3) - 1.0, float(i / 3) - 1.0);
        if (found || n.x < 0.0 || n.y < 0.0 || n.x >= cols || n.y >= rows) continue;
        vec4 s = texture(state, (n + 0.5) / grid);
        if (s.a <= 0.0 || s.b >= 1.0) continue;
        vec2 p = (n + s.xy) * cellPx;
        vec2 q = (p + windVel(p) * dt) / cellPx;
        if (floor(q) == c) { found = true; res = vec4(fract(q), s.b + dt / s.a, s.a); }
    }
    if (!found) {
        float seed = fract(time * 0.618);
        res = vec4(hash22(c + seed * 97.0),
                   own.a <= 0.0 ? hash12(c * 1.7 + 3.0) : 0.0,     // premier tour : âges étalés
                   mix(1.8, 4.5, hash12(c * 0.9 + seed * 53.0)));
    }
    fragColor = res;
}
