#version 440
#extension GL_GOOGLE_include_directive : enable
// Vent, étape 2 : traînées. Texture de la taille de la carte, relue à l'image suivante : l'ancienne
// intensité s'estompe, puis on trace le dernier pas de chaque particule des 3 × 3 cases voisines.
// Sortie = blanc prémultiplié, affichée telle quelle par la ShaderEffectSource.
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
layout(binding = 3) uniform sampler2D trail;
#include "weather-common.glsl"
#include "weather-wind-common.glsl"

const float FADE = 0.93;             // part de traînée gardée à chaque image (30 i/s)

float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
    return length(p - a - ab * t);
}

void main() {
    vec2 px = qt_TexCoord0 * vec2(vw, vh);
    vec2 grid = vec2(cols, rows);
    vec2 c = floor(px / cellPx);
    float head = 0.0;
    for (int k = 0; k < 9; k++) {
        vec2 n = c + vec2(float(k % 3) - 1.0, float(k / 3) - 1.0);
        if (n.x < 0.0 || n.y < 0.0 || n.x >= cols || n.y >= rows) continue;
        vec4 s = texture(state, (n + 0.5) / grid);
        if (s.a <= 0.0 || s.b >= 1.0) continue;
        vec2 p = (n + s.xy) * cellPx;
        // naissance et mort en fondu, comme chez Apple
        float life = smoothstep(0.0, 0.15, s.b) * (1.0 - smoothstep(0.7, 1.0, s.b));
        head = max(head, 0.75 * life * (1.0 - smoothstep(0.15, 0.85, segDist(px, p - windVel(p) * dt, p))));
    }
    float a = max(texture(trail, qt_TexCoord0).a * FADE - 0.004, head) * insideGrid(gridAt(geoAt(px)));
    a = clamp(a, 0.0, 1.0);
    fragColor = vec4(a, a, a, a);
}
