// Partagé par weather-particles.frag et weather-trails.frag (après weather-common.glsl).
const float K = 2.0;                 // px/s par km/h : vitesse à l'écran indépendante du zoom

float hash12(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
vec2 hash22(vec2 p) { vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973)); q += dot(q, q.yzx + 33.33); return fract((q.xx + q.yz) * q.zy); }

// vitesse à l'écran (px/s) au point p (px de la carte), interpolée entre les heures A et B
vec2 windVel(vec2 p) {
    vec2 w = windMix(gridAt(geoAt(p)));
    return vec2(w.x, -w.y) * K;
}
