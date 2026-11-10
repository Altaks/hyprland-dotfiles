// Orbe animé de thinkingorbs.com (MIT, Yogesh) pour les états de chargement du tableau de bord.
// Les boucles sont exportées une fois pour toutes par export.mjs (projet vicinae-extensions/orbs) dans
// ~/.local/share/thinking-orbs/<état>.json : pour chaque image, x, y, rayon et opacité de chaque point
// (orbe de 20 px). On les redessine ici sur un Canvas, à la taille et dans la couleur voulues
// (couleur d'accent Pywal par défaut), uniquement quand l'orbe est visible.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: orb
    property string look: "working"      // working | reasoning | searching | background | waiting
    property color color: "#c6a0f6"
    property int size: 48
    property bool running: visible
    implicitWidth: size
    implicitHeight: size

    property var loop: null
    property int frame: 0

    FileView {
        id: src
        path: Quickshell.env("HOME") + "/.local/share/thinking-orbs/" + orb.look + ".json"
        onLoaded: { try { orb.loop = JSON.parse(text()); orb.frame = 0 } catch (e) { orb.loop = null } }
    }

    Timer {
        interval: orb.loop ? Math.round(1000 / orb.loop.fps) : 33
        repeat: true
        running: orb.running && orb.visible && !!orb.loop
        onTriggered: { orb.frame = (orb.frame + 1) % orb.loop.frames.length; cv.requestPaint() }
    }

    Canvas {
        id: cv
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const l = orb.loop
            if (!l) return
            const f = l.frames[orb.frame], k = width / l.size
            ctx.fillStyle = orb.color
            for (let i = 0; i < f.length; i += 4) {
                ctx.globalAlpha = Math.min(1, f[i + 3] * 1.15)
                ctx.beginPath()
                ctx.arc(f[i] * k, f[i + 1] * k, Math.max(0.6, f[i + 2] * k), 0, 2 * Math.PI)
                ctx.fill()
            }
        }
    }
    onColorChanged: cv.requestPaint()
}
