// Carte Naolib à tuiles (onglet Nantes du tableau de bord), chargée par un Loader dans shell.qml :
// si QtLocation manque (paquets qml6-module-qtlocation + qt6-location-plugins), le Loader échoue et
// shell.qml garde sa carte dessinée sur Canvas.
// Tuiles : Esri « Dark Gray Canvas » (fond + couche de noms, sans clé ; CARTO en exige une désormais),
// cache disque géré par le plugin osm de Qt. Trois cartes superposées et synchronisées : fond, noms,
// puis une carte transparente (plugin itemsoverlay) qui porte les gestes, les tracés et les véhicules.
// Accède à root (couleurs, police, données naolib/naoMap/route) par le contexte du Loader.
import QtQuick
import QtLocation
import QtPositioning

Item {
    id: nm
    property real now: Date.now() / 1000
    property var hover: null
    property int count: 0
    readonly property var lines: root.naoMap?.lines ?? []
    readonly property var routePath: root.route?.routes?.[root.routeSel]?.path ?? []
    // un tracé par élément, bus d'abord pour que les trams passent par-dessus
    readonly property var paths: {
        const out = []
        for (const l of lines.slice().reverse()) for (const p of l.paths) out.push({ color: l.color, tram: l.type === 0, path: p.map(coord) })
        return out
    }

    Timer {
        interval: 250; repeat: true; running: nm.visible
        onTriggered: {
            nm.now = Date.now() / 1000
            nm.count = (root.naolib?.vehicles ?? []).filter(v => nm.pos(v, nm.now)).length
        }
    }

    function coord(p) { return QtPositioning.coordinate(p[0], p[1]) }
    function fitTo(pts, margin) {
        if (!pts.length) return
        view.map.fitViewportToGeoShape(QtPositioning.path(pts.map(coord)), margin ?? 60)
    }
    function fitNetwork() {
        const pts = []
        for (const l of lines) for (const path of l.paths) for (const p of path) pts.push(p)
        fitTo(pts, 30)
    }
    function zoomBy(f) { view.map.zoomLevel += Math.log2(f) }
    // position d'un véhicule à l'instant t (interpolation entre deux arrêts)
    function pos(v, t) {
        const p = v.p
        if (!p.length || t < p[0][0] || t > p[p.length - 1][0]) return null
        for (let i = 1; i < p.length; i++) if (t <= p[i][0]) {
            const a = p[i - 1], b = p[i], f = b[0] === a[0] ? 1 : (t - a[0]) / (b[0] - a[0])
            return { lat: a[1] + (b[1] - a[1]) * f, lon: a[2] + (b[2] - a[2]) * f, next: b[3] }
        }
        return null
    }

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
        bearing: view.map.bearing
        tilt: view.map.tilt
        copyrightsVisible: false
        enabled: false
    }
    Layer { plugin: EsriTiles { layer: "World_Dark_Gray_Base" } color: root.bg }
    Layer { plugin: EsriTiles { layer: "World_Dark_Gray_Reference" } color: "transparent" }

    MapView {
        id: view
        anchors.fill: parent
        map.plugin: Plugin { name: "itemsoverlay" }
        map.color: "transparent"
        map.center: QtPositioning.coordinate(47.212, -1.556)
        map.zoomLevel: 12.3
        map.copyrightsVisible: false
        // cadrage initial une fois la carte dimensionnée et les tracés chargés
        property bool fitted: false
        function tryFit() { if (!fitted && width > 0 && nm.lines.length) { fitted = true; Qt.callLater(nm.fitNetwork) } }
        onWidthChanged: tryFit()
        Connections { target: nm; function onLinesChanged() { view.tryFit() } }
        Component.onCompleted: tryFit()

        // Tracés des lignes
        MapItemView {
            parent: view.map
            model: nm.paths
            delegate: MapPolyline {
                required property var modelData
                line.color: modelData.color
                line.width: modelData.tram ? 4 : 2.5
                opacity: modelData.tram ? 0.9 : 0.6
                path: modelData.path
            }
        }

        // Arrêts de tram
        MapItemView {
            parent: view.map
            model: root.naoMap?.stops ?? []
            delegate: MapQuickItem {
                required property var modelData
                coordinate: QtPositioning.coordinate(modelData[1], modelData[2])
                anchorPoint { x: 3.5; y: 3.5 }
                zoomLevel: 0
                sourceItem: Rectangle {
                    width: 7; height: 7; radius: 3.5
                    color: root.bg
                    border { width: 1.2; color: root.fg }
                }
            }
        }

        // Itinéraire choisi
        MapItemView {
            parent: view.map
            model: nm.routePath.length > 1 ? [nm.routePath.map(nm.coord)] : []
            delegate: MapPolyline {
                required property var modelData
                line.color: root.accent
                line.width: 5
                path: modelData
            }
        }

        // Véhicules (positions recalculées 4 fois par seconde)
        MapItemView {
            id: vehicles
            parent: view.map
            model: root.naolib?.vehicles ?? []
            delegate: MapQuickItem {
                id: veh
                required property var modelData
                readonly property var q: nm.pos(modelData, nm.now)
                readonly property bool tram: modelData.type === 0
                visible: !!q
                coordinate: q ? QtPositioning.coordinate(q.lat, q.lon) : QtPositioning.coordinate()
                anchorPoint { x: dot.width / 2; y: dot.height / 2 }
                sourceItem: Rectangle {
                    id: dot
                    width: veh.tram ? 18 : 15; height: width; radius: width / 2
                    color: veh.modelData.color
                    border { width: 1.8; color: veh.modelData.rt ? (root.wal ? root.wal.colors.color2 : "#a6da95") : root.bg }
                    Text {
                        anchors.centerIn: parent
                        text: veh.modelData.line
                        color: veh.modelData.text
                        font { family: root.font; pixelSize: veh.tram ? 9 : 7; bold: true }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: nm.hover = containsMouse ? { v: veh.modelData, q: veh.q, item: dot } : (nm.hover?.v === veh.modelData ? null : nm.hover)
                    }
                }
            }
        }
    }

    // Infobulle du véhicule survolé
    Rectangle {
        visible: !!nm.hover
        readonly property point at: nm.hover ? nm.hover.item.mapToItem(nm, nm.hover.item.width, nm.hover.item.height) : Qt.point(0, 0)
        x: Math.min(at.x + 6, nm.width - width - 8); y: at.y + 6
        width: tipCol.implicitWidth + 20; height: tipCol.implicitHeight + 14; radius: 10
        color: root.bg
        border { width: 1; color: root.surface }
        Column {
            id: tipCol
            anchors.centerIn: parent
            Text { text: "Ligne " + (nm.hover?.v.line ?? "") + " → " + (nm.hover?.v.headsign ?? ""); color: root.fg; font { family: root.font; pixelSize: 12; bold: true } }
            Text { text: "Prochain arrêt : " + (nm.pos(nm.hover?.v ?? { p: [] }, nm.now)?.next ?? ""); color: root.dim; font { family: root.font; pixelSize: 11 } }
            Text { text: nm.hover?.v.rt ? "position recalée en temps réel" : "horaire théorique"; color: root.dim; font { family: root.font; pixelSize: 10 } }
        }
    }

    // Attribution exigée par OpenStreetMap / CARTO
    Text {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 56; bottomMargin: 8 }
        text: "Fond © Esri, HERE, Garmin, © OpenStreetMap"
        color: root.dim
        font { family: root.font; pixelSize: 9 }
    }
}
