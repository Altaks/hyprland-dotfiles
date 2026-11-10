// Carte météo façon Apple Météo (onglet Météo du tableau de bord), chargée par un Loader dans shell.qml.
// Calques : précipitations (radar RainViewer des 2 dernières heures puis prévision Open-Meteo),
// vent (particules animées sur un fond coloré par la vitesse), température et qualité de l'air (EAQI). Données : root.weatherMap
// (~/.local/bin/weather-map-fetch) ; le calque « relevant » choisi par le script s'affiche par défaut.
// À l'ouverture : vue centrée sur la ville et lecture automatique, en fondu continu entre les pas de temps.
// Rendu : fond coloré et traînées de vent sont des shaders GPU (shaders/weather-*.frag.qsb) qui lisent
// l'atlas PNG de la grille ; le processeur ne fait que mettre à jour quelques uniformes.
// Fond Esri Dark Gray comme NaoMap.qml ; projection Web Mercator calculée à partir du centre et du zoom
// de la carte (ni rotation ni inclinaison).
import QtQuick
import QtLocation
import QtPositioning

Item {
    id: wm
    readonly property var d: root.weatherMap
    readonly property var g: d?.grid ?? null
    readonly property var radar: d?.radar ?? null
    property string pick: ""                                   // rain | wind | temp | air ; "" = calque conseillé
    readonly property string shown: pick || d?.relevant || "temp"
    readonly property real homeZoom: 8
    readonly property real cz: view.map.zoomLevel
    readonly property real clat: view.map.center.latitude
    readonly property real clon: view.map.center.longitude

    // Pas de temps du curseur : radar passé puis prévisions horaires pour la pluie, 24 h sinon
    readonly property var frames: {
        const out = [], times = g?.times ?? []
        if (shown === "rain") {
            const rf = radar?.frames ?? []
            rf.forEach((f, i) => out.push({ t: f.time, r: i, h: -1 }))
            const last = rf.length ? rf[rf.length - 1].time : 0
            times.forEach((t, h) => { if (t > last + 1800 && out.length < rf.length + 12) out.push({ t: t, r: -1, h: h }) })
        } else times.forEach((t, h) => out.push({ t: t, r: -1, h: h }))
        return out
    }
    // Position continue dans les pas de temps : fondu entre A (partie entière) et B (suivant)
    property real pos: 0
    readonly property int last: Math.max(0, frames.length - 1)
    readonly property int ia: Math.min(Math.floor(pos), last)
    readonly property real frac: Math.min(1, Math.max(0, pos - ia))
    readonly property var fa: frames[ia] ?? null
    readonly property var fb: frames[Math.min(ia + 1, last)] ?? null
    readonly property var cur: frames[Math.min(Math.round(pos), last)] ?? null
    function weightH(h) { return (fa?.h === h ? 1 - frac : 0) + (fb?.h === h ? frac : 0) }
    function weightR(r) { return (fa?.r === r ? 1 - frac : 0) + (fb?.r === r ? frac : 0) }
    // indice de « maintenant » : dernière image radar, ou heure en cours
    function nowIndex() {
        const now = Date.now() / 1000
        let best = 0
        frames.forEach((f, i) => { if (f.t <= now) best = i })
        return best
    }
    // la pluie se rejoue depuis le passé, les autres calques depuis maintenant
    function startPos() { return shown === "rain" ? 0 : nowIndex() }

    property bool playing: false
    property int hold: 0
    function start() {
        if (!g) return
        recenter()
        pos = startPos()
        hold = 0
        playing = true
    }
    // Horloge unique à 30 images/s (lecture + temps des traînées de vent) : au-delà, le processeur
    // ne ferait que relancer le rendu à la fréquence de l'écran (165 Hz) pour un gain invisible
    property real clock: 0
    Timer {
        interval: 33
        repeat: true
        running: wm.visible && (wm.playing || wm.shown === "wind")
        onTriggered: {
            if (wm.shown === "wind") wm.clock = (wm.clock + interval / 1000) % 1000
            if (!wm.playing) return
            if (wm.pos < wm.last) { wm.pos = Math.min(wm.last, wm.pos + (wm.shown === "rain" ? 0.066 : 0.075)); return }
            // pause sur la dernière image puis on reboucle
            if (++wm.hold > 48) { wm.hold = 0; wm.pos = wm.startPos() }
        }
    }
    onShownChanged: start()
    onVisibleChanged: if (visible) start()
    onGChanged: if (g && !playing) start()
    onFramesChanged: if (pos > last) pos = startPos()

    // --- Web Mercator (tuiles de 256 px) ---
    function wx(lon, z) { return (lon + 180) / 360 * 256 * Math.pow(2, z) }
    function wy(lat, z) {
        const s = Math.sin(lat * Math.PI / 180)
        return (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * 256 * Math.pow(2, z)
    }
    function sx(lon) { return wx(lon, cz) - wx(clon, cz) + width / 2 }
    function sy(lat) { return wy(lat, cz) - wy(clat, cz) + height / 2 }
    function tileLat(y, z) { return Math.atan(Math.sinh(Math.PI * (1 - 2 * y / Math.pow(2, z)))) * 180 / Math.PI }

    // Palettes [valeur, r, g, b, alpha] pour la légende ; à garder identiques à shaders/weather-heat.frag
    readonly property var palettes: ({
        temp: [[-15, 120, 60, 170, 255], [-5, 90, 90, 215, 255], [0, 70, 130, 230, 255], [6, 60, 180, 220, 255], [12, 90, 200, 140, 255],
               [17, 180, 215, 80, 255], [22, 245, 205, 70, 255], [27, 245, 150, 60, 255], [32, 230, 80, 60, 255], [38, 170, 30, 60, 255]],
        rain: [[0.05, 110, 180, 255, 0], [0.2, 110, 180, 255, 150], [1, 50, 120, 255, 210], [3, 40, 200, 110, 225],
               [6, 250, 215, 60, 235], [12, 245, 110, 50, 245], [25, 200, 60, 210, 255]],
        wind: [[0, 85, 95, 200, 200], [10, 70, 140, 215, 205], [20, 60, 185, 195, 210], [30, 90, 200, 120, 215],
               [45, 225, 215, 75, 220], [60, 240, 150, 55, 225], [80, 225, 70, 70, 230], [100, 175, 50, 170, 235]],
        air: [[10, 80, 240, 230, 225], [30, 80, 204, 170, 225], [50, 240, 230, 65, 230], [70, 255, 80, 80, 235],
              [90, 150, 0, 50, 240], [110, 125, 33, 129, 240]]
    })
    function colour(pal, v) {
        if (v <= pal[0][0]) return pal[0]
        for (let k = 1; k < pal.length; k++) if (v <= pal[k][0]) {
            const a = pal[k - 1], b = pal[k], f = (v - a[0]) / (b[0] - a[0])
            return [v, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f, a[4] + (b[4] - a[4]) * f]
        }
        return pal[pal.length - 1]
    }
    // Valeur au point de la ville, interpolée entre A et B
    function here(key) {
        const a = d?.here?.[key]
        if (!a) return null
        if (fa?.h >= 0 && fb?.h >= 0) return a[fa.h] * (1 - frac) + a[fb.h] * frac
        if (fb?.h >= 0 && frac > 0.5) return a[fb.h]
        return fa?.h >= 0 ? a[fa.h] : null
    }

    function recenter() {
        if (d?.lat === undefined) return
        view.map.center = QtPositioning.coordinate(d.lat, d.lon)
        view.map.zoomLevel = homeZoom
    }
    Component.onCompleted: start()

    component EsriTiles: Plugin {
        property string layer
        name: "osm"
        PluginParameter { name: "osm.mapping.custom.host"; value: "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/" + layer + "/MapServer/tile/%z/%y/%x" }
        PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
        PluginParameter { name: "osm.useragent"; value: "hantrox-dashboard/1.0 (Quickshell)" }
        PluginParameter { name: "osm.mapping.cache.directory"; value: root.home + "/.cache/dashboard-naolib/tiles/" + layer }
    }
    component Layer: Map {
        anchors.fill: parent
        activeMapType: supportedMapTypes[supportedMapTypes.length - 1]  // « Custom URL Map »
        center: view.map.center
        zoomLevel: view.map.zoomLevel
        copyrightsVisible: false
        enabled: false
    }
    Layer { plugin: EsriTiles { layer: "World_Dark_Gray_Base" } color: root.bg }

    // --- Radar : tuiles RainViewer (zoom 7 max), toutes les images préchargées, fondu entre deux images ---
    readonly property int tz: Math.max(2, Math.min(7, Math.round(cz)))
    readonly property string tileKey: {
        if (!radar || width <= 0 || shown !== "rain") return ""
        const n = Math.pow(2, tz), size = 256 * Math.pow(2, cz)
        const x0 = Math.floor((wx(clon, cz) - width / 2) / size * n), x1 = Math.floor((wx(clon, cz) + width / 2) / size * n)
        const y0 = Math.max(0, Math.floor((wy(clat, cz) - height / 2) / size * n)), y1 = Math.min(n - 1, Math.floor((wy(clat, cz) + height / 2) / size * n))
        const keys = []
        for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) keys.push(tz + "/" + x + "/" + y)
        return keys.join(" ")
    }
    Item {
        anchors.fill: parent
        opacity: 0.85
        Repeater {
            model: wm.tileKey ? wm.tileKey.split(" ") : []
            delegate: Item {
                id: tile
                required property string modelData
                readonly property var zxy: modelData.split("/").map(Number)
                readonly property int n: Math.pow(2, zxy[0])
                x: wm.sx(zxy[1] / n * 360 - 180); y: wm.sy(wm.tileLat(zxy[2], zxy[0]))
                width: wm.sx((zxy[1] + 1) / n * 360 - 180) - x
                height: wm.sy(wm.tileLat(zxy[2] + 1, zxy[0])) - y
                Repeater {
                    model: wm.radar?.frames ?? []
                    delegate: Image {
                        required property var modelData
                        required property int index
                        anchors.fill: parent
                        opacity: wm.weightR(index)          // 0 = non dessinée, mais déjà chargée
                        asynchronous: true
                        smooth: true
                        source: wm.radar.host + modelData.path + "/256/" + tile.zxy[0] + "/" + (((tile.zxy[1] % tile.n) + tile.n) % tile.n)
                                + "/" + tile.zxy[2] + "/2/1_1.png"
                    }
                }
            }
        }
    }

    // --- Calques calculés sur le GPU (shaders/weather-*.frag) à partir de l'atlas de weather-map-fetch :
    //     rien n'est dessiné par le processeur, seuls des uniformes changent d'une image à l'autre ---
    Image {
        id: atlasImg
        visible: false
        smooth: true                       // filtrage linéaire = interpolation bilinéaire de la grille
        cache: false
        source: wm.d?.atlas ? "file://" + wm.d.atlas : ""
    }
    // heures lues par les shaders : A et B quand les deux sont des prévisions, sinon B en fondu depuis le radar
    readonly property int hourA: fa?.h >= 0 ? fa.h : (fb?.h ?? 0)
    readonly property int hourB: fb?.h >= 0 ? fb.h : hourA
    readonly property real mixAB: fa?.h >= 0 && fb?.h >= 0 ? frac : 0
    readonly property real gridShown: fa?.h >= 0 ? 1 : fb?.h >= 0 ? frac : 0
    component GeoShader: ShaderEffect {
        anchors.fill: parent
        readonly property var atlas: atlasImg
        // géométrie de la carte entière (pas de l'élément : la simulation du vent est une petite texture)
        readonly property real vw: wm.width
        readonly property real vh: wm.height
        readonly property real worldSize: 256 * Math.pow(2, wm.cz)
        readonly property real x0: wm.wx(wm.clon, wm.cz) - wm.width / 2
        readonly property real y0: wm.wy(wm.clat, wm.cz) - wm.height / 2
        readonly property real lon0: wm.g?.lon0 ?? 0
        readonly property real lat0: wm.g?.lat0 ?? 0
        readonly property real dlon: wm.g?.dlon ?? 1
        readonly property real dlat: wm.g?.dlat ?? 1
        readonly property real nlon: wm.g?.nlon ?? 1
        readonly property real nlat: wm.g?.nlat ?? 1
        readonly property real hours: wm.g?.times.length ?? 1
        readonly property real hourA: wm.hourA
        readonly property real hourB: wm.hourB
        readonly property real mixAB: wm.mixAB
        readonly property real mode: ({ temp: 0, rain: 1, wind: 2, air: 3 })[wm.shown]
        property real time: 0
        visible: !!wm.g && atlasImg.status === Image.Ready && opacity > 0.001
    }
    // Fond coloré : température, pluie prévue ou vitesse du vent
    GeoShader {
        fragmentShader: "shaders/weather-heat.frag.qsb"
        opacity: wm.gridShown * ({ temp: 0.55, rain: 0.85, wind: 0.7, air: 0.6 })[wm.shown]
    }

    Layer { plugin: EsriTiles { layer: "World_Dark_Gray_Reference" } color: "transparent" }

    // Vent : vraies particules simulées sur le GPU, en deux passes rebouclées sur elles-mêmes
    // (ShaderEffectSource récursives) : weather-particles.frag fait avancer une particule par case de
    // cellPx px, weather-trails.frag trace leur dernier pas sur l'image précédente estompée.
    // Une image de simulation par tic de wm.clock (30 i/s) : live: false, sinon une source récursive se
    // recalcule à chaque rafraîchissement de l'écran (165 Hz) et le vent file 5 fois trop vite.
    Item {
        id: windFx
        anchors.fill: parent
        visible: wm.shown === "wind" && !!wm.g && atlasImg.status === Image.Ready
        opacity: wm.gridShown * 0.8
        readonly property real cellPx: 20
        readonly property real cols: Math.ceil(width / cellPx)
        readonly property real rows: Math.ceil(height / cellPx)
        Connections {
            target: wm
            function onClockChanged() { if (windFx.visible) { partSrc.scheduleUpdate(); trailSrc.scheduleUpdate() } }
        }
        component WindPass: GeoShader {
            readonly property var state: partSrc
            readonly property real cols: windFx.cols
            readonly property real rows: windFx.rows
            readonly property real cellPx: windFx.cellPx
            readonly property real dt: 1 / 30
            time: wm.clock
            visible: true
        }
        WindPass {
            id: partFx
            anchors.fill: undefined
            width: windFx.cols; height: windFx.rows
            fragmentShader: "shaders/weather-particles.frag.qsb"
        }
        ShaderEffectSource {
            id: partSrc
            visible: false
            sourceItem: partFx
            hideSource: true
            recursive: true
            live: false
            format: ShaderEffectSource.RGBA16F
            smooth: false
            textureSize: Qt.size(windFx.cols, windFx.rows)
        }
        WindPass {
            id: trailFx
            readonly property var trail: trailSrc
            fragmentShader: "shaders/weather-trails.frag.qsb"
        }
        ShaderEffectSource {
            id: trailSrc
            anchors.fill: parent
            sourceItem: trailFx
            hideSource: true
            recursive: true
            live: false
            format: ShaderEffectSource.RGBA16F
        }
    }

    // --- Gestes + position de la ville ---
    MapView {
        id: view
        anchors.fill: parent
        map.plugin: Plugin { name: "itemsoverlay" }
        map.color: "transparent"
        map.center: QtPositioning.coordinate(wm.d?.lat ?? 47.2, wm.d?.lon ?? -1.55)
        map.zoomLevel: wm.homeZoom
        map.minimumZoomLevel: 5
        map.maximumZoomLevel: 15
        map.copyrightsVisible: false
        map.bearing: 0
        map.tilt: 0

        MapQuickItem {
            parent: view.map
            visible: wm.d?.lat !== undefined
            coordinate: QtPositioning.coordinate(wm.d?.lat ?? 0, wm.d?.lon ?? 0)
            anchorPoint { x: pin.width / 2; y: pin.height - 7 }
            sourceItem: Column {
                id: pin
                spacing: 3
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: bubble.text !== ""
                    width: bubble.implicitWidth + 16; height: 24; radius: 12
                    color: root.bg
                    border { width: 1; color: root.surface }
                    Text {
                        id: bubble
                        readonly property var v: wm.here(wm.shown)
                        anchors.centerIn: parent
                        text: v === null ? ""
                            : wm.shown === "temp" ? Math.round(v) + "°"
                            : wm.shown === "wind" ? Math.round(v) + " km/h"
                            : wm.shown === "air" ? "IQA " + Math.round(v)
                            : v >= 0.05 ? v.toFixed(1) + " mm" : "Sec"
                        color: root.fg
                        font { family: root.font; pixelSize: 12; bold: true }
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 14; height: 14; radius: 7
                    color: root.accent
                    border { width: 2.5; color: "white" }
                }
            }
        }
    }

    // ===================== Commandes =====================
    // Calques
    Column {
        anchors { left: parent.left; top: parent.top; margins: 12 }
        spacing: 6
        Row {
            spacing: 6
            Repeater {
                model: [["rain", "󰖗", "Pluie"], ["wind", "󰖝", "Vent"], ["temp", "󰔏", "Température"]]
                       .concat(wm.g?.air ? [["air", "󰌪", "Air"]] : [])
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool on: wm.shown === modelData[0]
                    width: chipRow.implicitWidth + 22; height: 30; radius: 15
                    color: on ? root.accent : Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.85)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: chip.modelData[1]; color: chip.on ? root.bg : root.fg; font { family: root.font; pixelSize: 15 } }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: chip.modelData[2]; color: chip.on ? root.bg : root.fg; font { family: root.font; pixelSize: 12; bold: chip.on } }
                    }
                    // pastille sur le calque conseillé
                    Rectangle {
                        visible: wm.d?.relevant === chip.modelData[0]
                        anchors { right: parent.right; top: parent.top; rightMargin: 2; topMargin: 2 }
                        width: 8; height: 8; radius: 4
                        color: chip.on ? root.bg : root.accent
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wm.pick = chip.modelData[0] }
                }
            }
        }
        Rectangle {
            visible: !!wm.d?.reason && wm.shown === wm.d.relevant
            width: reasonText.implicitWidth + 20; height: 26; radius: 13
            color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.85)
            Text {
                id: reasonText
                anchors.centerIn: parent
                text: "󰀦  " + (wm.d?.reason ?? "")
                color: root.fg
                font { family: root.font; pixelSize: 11 }
            }
        }
    }

    // Agrandir / recentrer
    Column {
        anchors { right: parent.right; top: parent.top; margins: 12 }
        spacing: 6
        Repeater {
            model: [[root.weatherMapFull ? "󰊔" : "󰊓", () => root.weatherMapFull = !root.weatherMapFull],
                    ["󰆤", () => wm.recenter()], ["󰐕", () => view.map.zoomLevel = Math.min(15, view.map.zoomLevel + 1)],
                    ["󰍴", () => view.map.zoomLevel = Math.max(5, view.map.zoomLevel - 1)]]
            delegate: Rectangle {
                required property var modelData
                width: 32; height: 32; radius: 16
                color: btnMa.containsMouse ? root.bg : Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.85)
                Text { anchors.centerIn: parent; text: parent.modelData[0]; color: root.fg; font { family: root.font; pixelSize: 16 } }
                MouseArea { id: btnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.modelData[1]() }
            }
        }
    }

    // Lecture + curseur temporel + légende
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
        height: 58; radius: 16
        color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.88)
        visible: wm.frames.length > 0

        Rectangle {
            id: playBtn
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: 36; height: 36; radius: 18
            color: root.accent
            Text { anchors.centerIn: parent; text: wm.playing ? "󰏤" : "󰐊"; color: root.bg; font { family: root.font; pixelSize: 18 } }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wm.playing = !wm.playing }
        }
        Text {
            id: when
            x: 56; y: 9
            width: 120
            readonly property real dt: (wm.cur?.t ?? 0) - Date.now() / 1000
            text: {
                const f = wm.cur
                if (!f) return ""
                if (f.r >= 0) return dt > -900 ? "Maintenant" : "Il y a " + Math.round(-dt / 60) + " min"
                if (dt > -3600 && dt <= 0) return "Maintenant"
                const t = new Date(f.t * 1000), today = new Date().getDate() === t.getDate()
                return (today ? "" : "Demain ") + t.getHours() + " h"
            }
            color: root.fg
            font { family: root.font; pixelSize: 13; bold: true }
        }
        Text {
            x: 56; anchors.top: when.bottom
            text: wm.cur ? (wm.cur.r >= 0 ? "radar" : "prévision") : ""
            color: root.dim
            font { family: root.font; pixelSize: 10 }
        }
        // Curseur
        Item {
            id: track
            anchors { left: parent.left; leftMargin: 180; right: legend.left; rightMargin: 24; verticalCenter: parent.verticalCenter }
            height: 24
            readonly property int n: Math.max(1, wm.frames.length - 1)
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: root.surface }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * wm.pos / track.n; height: 4; radius: 2
                color: root.accent
            }
            // repère « maintenant »
            Rectangle {
                x: parent.width * wm.nowIndex() / track.n - 1
                anchors.verticalCenter: parent.verticalCenter
                width: 2; height: 14; radius: 1
                color: root.fg
                opacity: 0.7
            }
            Rectangle {
                x: parent.width * wm.pos / track.n - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16; radius: 8
                color: root.fg
                border { width: 3; color: root.accent }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function seek(x) { wm.playing = false; wm.pos = Math.max(0, Math.min(1, x / width)) * track.n }
                onPressed: mouse => seek(mouse.x)
                onPositionChanged: mouse => { if (pressed) seek(mouse.x) }
            }
        }
        // Légende
        Column {
            id: legend
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: 170
            spacing: 4
            readonly property var pal: wm.palettes[wm.shown]
            readonly property var ticks: wm.shown === "temp" ? ["-10°", "0°", "10°", "20°", "30°"]
                                       : wm.shown === "wind" ? ["0", "25", "50", "75 km/h"]
                                       : wm.shown === "air" ? ["bonne", "dégradée", "mauvaise"] : ["faible", "modérée", "forte"]
            Rectangle {
                width: parent.width; height: 8; radius: 4
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: legend.stop(0) }
                    GradientStop { position: 0.25; color: legend.stop(0.25) }
                    GradientStop { position: 0.5; color: legend.stop(0.5) }
                    GradientStop { position: 0.75; color: legend.stop(0.75) }
                    GradientStop { position: 1.0; color: legend.stop(1) }
                }
            }
            function stop(f) {
                const lo = ({ temp: -10, wind: 0, air: 10, rain: 0.2 })[wm.shown]
                const hi = ({ temp: 30, wind: 75, air: 90, rain: 15 })[wm.shown]
                const v = wm.shown === "rain" ? lo * Math.pow(hi / lo, f) : lo + (hi - lo) * f
                const c = wm.colour(pal, v)
                return Qt.rgba(c[1] / 255, c[2] / 255, c[3] / 255, wm.shown === "temp" ? 1 : Math.max(0.35, c[4] / 255))
            }
            Item {
                width: parent.width; height: 12
                Repeater {
                    model: legend.ticks
                    delegate: Text {
                        required property string modelData
                        required property int index
                        x: index === 0 ? 0 : index === legend.ticks.length - 1 ? legend.width - implicitWidth
                           : legend.width * index / (legend.ticks.length - 1) - implicitWidth / 2
                        text: modelData
                        color: root.dim
                        font { family: root.font; pixelSize: 9 }
                    }
                }
            }
        }
    }

    Text {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 14; bottomMargin: 72 }
        text: "Fond © Esri · radar RainViewer · prévisions Open-Meteo"
        color: root.dim
        font { family: root.font; pixelSize: 9 }
    }
}
