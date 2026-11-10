#version 440
#extension GL_GOOGLE_include_directive : enable
// Fond coloré de la carte météo (température, pluie prévue, vitesse du vent ou qualité de l'air),
// fondu entre deux heures.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float vw; float vh;              // taille de l'élément (px)
    float x0; float y0;              // coin haut-gauche en pixels « monde » au zoom courant
    float worldSize;                 // 256 · 2^zoom
    float lon0; float lat0; float dlon; float dlat;
    float nlon; float nlat; float hours;
    float hourA; float hourB; float mixAB;
    float mode;                      // 0 température, 1 pluie, 2 vitesse du vent, 3 qualité de l'air
};
layout(binding = 1) uniform sampler2D atlas;
#include "weather-common.glsl"

// mêmes paliers que wm.palettes dans WeatherMap.qml (légende) : valeur, puis rgba
vec4 ramp(float v, const float st[10], const vec4 col[10], int n) {
    if (v <= st[0]) return col[0];
    for (int k = 1; k < n; k++)
        if (v <= st[k]) return mix(col[k - 1], col[k], (v - st[k - 1]) / (st[k] - st[k - 1]));
    return col[n - 1];
}
const float TS[10] = float[](-15.0, -5.0, 0.0, 6.0, 12.0, 17.0, 22.0, 27.0, 32.0, 38.0);
const vec4 TC[10] = vec4[](vec4(120, 60, 170, 255), vec4(90, 90, 215, 255), vec4(70, 130, 230, 255), vec4(60, 180, 220, 255),
    vec4(90, 200, 140, 255), vec4(180, 215, 80, 255), vec4(245, 205, 70, 255), vec4(245, 150, 60, 255), vec4(230, 80, 60, 255), vec4(170, 30, 60, 255));
const float RS[10] = float[](0.05, 0.2, 1.0, 3.0, 6.0, 12.0, 25.0, 0.0, 0.0, 0.0);
const vec4 RC[10] = vec4[](vec4(110, 180, 255, 0), vec4(110, 180, 255, 150), vec4(50, 120, 255, 210), vec4(40, 200, 110, 225),
    vec4(250, 215, 60, 235), vec4(245, 110, 50, 245), vec4(200, 60, 210, 255), vec4(0), vec4(0), vec4(0));
const float WS[10] = float[](0.0, 10.0, 20.0, 30.0, 45.0, 60.0, 80.0, 100.0, 0.0, 0.0);
const vec4 WC[10] = vec4[](vec4(85, 95, 200, 200), vec4(70, 140, 215, 205), vec4(60, 185, 195, 210), vec4(90, 200, 120, 215),
    vec4(225, 215, 75, 220), vec4(240, 150, 55, 225), vec4(225, 70, 70, 230), vec4(175, 50, 170, 235), vec4(0), vec4(0));
// indice européen : couleurs de l'Agence européenne pour l'environnement, au milieu de chaque classe
const float AS[10] = float[](10.0, 30.0, 50.0, 70.0, 90.0, 110.0, 0.0, 0.0, 0.0, 0.0);
const vec4 AC[10] = vec4[](vec4(80, 240, 230, 225), vec4(80, 204, 170, 225), vec4(240, 230, 65, 230), vec4(255, 80, 80, 235),
    vec4(150, 0, 50, 240), vec4(125, 33, 129, 240), vec4(0), vec4(0), vec4(0), vec4(0));

void main() {
    vec2 g = gridAt(geoAt(qt_TexCoord0 * vec2(vw, vh)));
    vec4 c;
    if (mode < 0.5) c = ramp(mix(tempAt(g, hourA), tempAt(g, hourB), mixAB), TS, TC, 10);
    else if (mode < 1.5) c = ramp(mix(rainAt(g, hourA), rainAt(g, hourB), mixAB), RS, RC, 7);
    else if (mode < 2.5) c = ramp(length(windMix(g)), WS, WC, 8);
    else c = ramp(mix(airAt(g, hourA), airAt(g, hourB), mixAB), AS, AC, 6);
    float a = c.a / 255.0 * insideGrid(g) * qt_Opacity;
    fragColor = vec4(c.rgb / 255.0 * a, a);
}
