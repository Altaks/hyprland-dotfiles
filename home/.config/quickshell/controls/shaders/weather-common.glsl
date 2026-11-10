// Partagé par les shaders weather-*.frag (#include). Après modification, recompiler :
//   for f in weather-heat weather-particles weather-trails; do /usr/lib/qt6/bin/qsb --glsl "300 es,330" -o $f.frag.qsb $f.frag; done
//   puis redémarrer (qs -c controls kill; setsid -f qs -c controls -d) : un rechargement garde l'ancien shader.
// Projection Web Mercator : pixel de l'élément → lon/lat, puis lecture de l'atlas écrit par
// ~/.local/bin/weather-map-fetch (une bande de nlat lignes par heure ; blocs : T, u, v | pluie | EAQI).

vec2 geoAt(vec2 frag) {
    float lon = (x0 + frag.x) / worldSize * 360.0 - 180.0;
    float n = 3.14159265 * (1.0 - 2.0 * (y0 + frag.y) / worldSize);
    return vec2(lon, degrees(atan(0.5 * (exp(n) - exp(-n)))));
}
vec2 gridAt(vec2 geo) { return vec2((geo.x - lon0) / dlon, (geo.y - lat0) / dlat); }
// 1 dans la grille, 0 une maille au-delà
float insideGrid(vec2 g) {
    vec2 o = max(-g, g - vec2(nlon - 1.0, nlat - 1.0));
    return clamp(1.0 - max(max(o.x, o.y), 0.0), 0.0, 1.0);
}
vec4 texel(vec2 g, float hour, float block) {
    vec2 c = clamp(g, vec2(0.0), vec2(nlon - 1.0, nlat - 1.0));
    return texture(atlas, vec2((block * nlon + c.x + 0.5) / (3.0 * nlon), (hour * nlat + c.y + 0.5) / (hours * nlat)));
}
float tempAt(vec2 g, float hr) { return texel(g, hr, 0.0).r * 80.0 - 30.0; }
vec2 windAt(vec2 g, float hr) { return texel(g, hr, 0.0).gb * 240.0 - 120.0; }
float rainAt(vec2 g, float hr) { float s = texel(g, hr, 1.0).r; return s * s * 30.0; }
float airAt(vec2 g, float hr) { return texel(g, hr, 2.0).r * 150.0; }
vec2 windMix(vec2 g) { return mix(windAt(g, hourA), windAt(g, hourB), mixAB); }
