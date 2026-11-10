// Vue d'ensemble des bureaux, façon Activités de GNOME.
// Glisser une fenêtre sur un bureau pour l'y déplacer, en l'aimantant selon l'endroit du lâcher
// (bords = moitiés, coins = quarts, haut = plein écran, centre = simple déplacement : ~/.local/bin/hypr-snap) ;
// clic sur une fenêtre pour y aller ;
// clic sur un bureau pour y aller ; Échap pour fermer.
// Ouverture : qs -c overview ipc call overview toggle   (Super+Tab)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property bool shown: false
    property var targetScreen: Quickshell.screens[0]

    // --- Couleurs Pywal ---
    FileView {
        id: walFile
        path: root.home + "/.cache/wal/colors.json"
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property var wal: {
        try { return JSON.parse(walFile.text()) } catch (e) { return null }
    }
    readonly property color bg: wal ? wal.special.background : "#161515"
    readonly property color fg: wal ? wal.special.foreground : "#c4c4c4"
    readonly property color accent: wal ? wal.colors.color4 : "#8aadf4"

    // Fond d'écran actuel (image fixe de la vidéo le cas échéant)
    FileView {
        id: currentFile
        path: root.home + "/.cache/hypr-wallpaper/current"
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property string wallpaper: {
        const p = currentFile.text().trim()
        return /\.(mp4|webm|mkv|mov)$/i.test(p) ? root.home + "/.cache/hypr-wallpaper/frame.jpg" : p
    }

    // Une rangée par écran : Samsung = bureaux 1..5, AOC = 6..10
    readonly property var workspaceIds: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    function workspace(id) { return Hyprland.workspaces.values.find(w => w.id === id) ?? null }
    function addr(t) { return t.address.startsWith("0x") ? t.address : "0x" + t.address }

    // --- Aimantation façon Windows/GNOME ---
    // Zone visée selon la position (u, v ∈ [0, 1]) du lâcher dans la vignette du bureau
    function zoneAt(u, v) {
        const l = u < 0.25, r = u > 0.75, t = v < 0.25, b = v > 0.75
        if (l && t) return "tl"
        if (r && t) return "tr"
        if (l && b) return "bl"
        if (r && b) return "br"
        if (l) return "left"
        if (r) return "right"
        if (v < 0.2) return "max"
        return "move"
    }
    // Rectangle de chaque zone, en fractions du bureau (même découpe que hypr-snap)
    readonly property var zoneRects: ({
        left: [0, 0, .5, 1], right: [.5, 0, .5, 1],
        tl: [0, 0, .5, .5], tr: [.5, 0, .5, .5], bl: [0, .5, .5, .5], br: [.5, .5, .5, .5],
        max: [0, 0, 1, 1]
    })

    // --- Ouverture sur l'écran de la souris ---
    Process {
        id: cursorQuery
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                let c = null
                try { c = JSON.parse(text) } catch (e) {}
                root.targetScreen = (c && Quickshell.screens.find(s =>
                        c.x >= s.x && c.x < s.x + s.width && c.y >= s.y && c.y < s.y + s.height))
                    ?? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
                    ?? Quickshell.screens[0]
                root.shown = true
            }
        }
    }
    function open() {
        if (shown) return
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        cursorQuery.running = true
    }
    function close() { shown = false }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.shown ? root.close() : root.open() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }

    // Les positions des fenêtres changent après un déplacement : on les relit.
    Timer { id: refresh; interval: 250; onTriggered: { Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels() } }

    PanelWindow {
        id: win
        visible: root.shown
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "overview"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: if (visible) keys.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.65)
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.close()

            readonly property int columns: 5
            readonly property real cardW: Math.min(480, (width - 120 - (columns - 1) * 28) / columns)
            readonly property real cardH: cardW * 9 / 16

            Flow {
                id: grid
                anchors.centerIn: parent
                width: keys.columns * keys.cardW + (keys.columns - 1) * spacing
                spacing: 28

                Repeater {
                    model: root.workspaceIds
                    delegate: Item {
                        id: card
                        required property int modelData
                        readonly property int wsId: modelData
                        readonly property var ws: root.workspace(wsId)
                        readonly property var mon: ws?.monitor ?? Hyprland.focusedMonitor
                        readonly property real k: mon ? keys.cardW / mon.width : 0.2
                        property bool dragging: false
                        property string zone: ""
                        width: keys.cardW
                        height: keys.cardH + 30
                        z: dragging ? 100 : 0

                        // Vignette du bureau
                        Rectangle {
                            id: frame
                            width: keys.cardW
                            height: keys.cardH
                            radius: 14
                            color: root.bg
                            clip: false
                            border.width: drop.containsDrag ? 4 : (card.ws?.active ? 3 : 1)
                            border.color: drop.containsDrag || card.ws?.active ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)

                            Image {
                                anchors { fill: parent; margins: 2 }
                                source: root.wallpaper ? "file://" + root.wallpaper : ""
                                sourceSize { width: 720; height: 405 }
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: 0.85
                            }

                            // Clic sur le bureau : y aller
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { Hyprland.dispatch("workspace " + card.wsId); root.close() }
                            }

                            // Réception d'une fenêtre glissée
                            DropArea {
                                id: drop
                                anchors.fill: parent
                                keys: ["window"]
                                onPositionChanged: d => card.zone = root.zoneAt(d.x / width, d.y / height)
                                onExited: card.zone = ""
                                onDropped: d => {
                                    const t = d.source.toplevel
                                    const zone = root.zoneAt(d.x / width, d.y / height)
                                    card.zone = ""
                                    if (t && (zone !== "move" || t.workspace?.id !== card.wsId)) {
                                        Quickshell.execDetached([root.home + "/.local/bin/hypr-snap", root.addr(t), String(card.wsId), zone])
                                        refresh.restart()
                                    }
                                }
                            }

                            // Aperçu de la zone d'aimantation pendant le glisser
                            Rectangle {
                                readonly property var r: root.zoneRects[card.zone] ?? null
                                visible: drop.containsDrag && r !== null
                                x: r ? 4 + r[0] * (parent.width - 8) : 0
                                y: r ? 4 + r[1] * (parent.height - 8) : 0
                                width: r ? r[2] * (parent.width - 8) : 0
                                height: r ? r[3] * (parent.height - 8) : 0
                                z: 40
                                radius: 10
                                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25)
                                border { width: 2; color: root.accent }
                                Behavior on x { NumberAnimation { duration: 90 } }
                                Behavior on y { NumberAnimation { duration: 90 } }
                                Behavior on width { NumberAnimation { duration: 90 } }
                                Behavior on height { NumberAnimation { duration: 90 } }
                            }

                            // Fenêtres du bureau, à leur position réelle
                            Repeater {
                                model: card.ws ? card.ws.toplevels.values.filter(t => t.lastIpcObject?.at && !t.lastIpcObject.hidden) : []
                                delegate: Item {
                                    id: slot
                                    required property var modelData
                                    readonly property var ipc: modelData.lastIpcObject
                                    x: (ipc.at[0] - (card.mon?.x ?? 0)) * card.k
                                    y: (ipc.at[1] - (card.mon?.y ?? 0)) * card.k
                                    width: Math.max(24, ipc.size[0] * card.k)
                                    height: Math.max(16, ipc.size[1] * card.k)
                                    z: tile.Drag.active ? 50 : (ipc.floating ? 2 : 1)

                                    Rectangle {
                                        id: tile
                                        property var toplevel: slot.modelData
                                        width: slot.width
                                        height: slot.height
                                        radius: 8
                                        color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.9)
                                        border.width: hover.containsMouse || Drag.active ? 2 : 1
                                        border.color: hover.containsMouse || Drag.active ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)
                                        clip: true
                                        scale: Drag.active ? 1.05 : 1
                                        Behavior on scale { NumberAnimation { duration: 120 } }

                                        Drag.active: hover.drag.active
                                        Drag.keys: ["window"]
                                        Drag.hotSpot.x: width / 2
                                        Drag.hotSpot.y: height / 2

                                        ScreencopyView {
                                            anchors { fill: parent; margins: 2 }
                                            captureSource: root.shown ? slot.modelData.wayland : null
                                            live: true
                                            constraintSize: Qt.size(width, height)
                                        }

                                        // Nom de la fenêtre au survol
                                        Rectangle {
                                            visible: hover.containsMouse && !tile.Drag.active
                                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 6 }
                                            width: Math.min(parent.width - 12, label.implicitWidth + 16)
                                            height: 22; radius: 11
                                            color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.9)
                                            Text {
                                                id: label
                                                anchors.centerIn: parent
                                                width: Math.min(implicitWidth, parent.width - 12)
                                                elide: Text.ElideRight
                                                text: slot.ipc.class || slot.modelData.title
                                                color: root.fg
                                                font { family: "CaskaydiaCove Nerd Font"; pixelSize: 11 }
                                            }
                                        }

                                        MouseArea {
                                            id: hover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            drag.target: tile
                                            drag.threshold: 6
                                            onPressed: card.dragging = true
                                            onReleased: {
                                                const moved = drag.active
                                                if (moved) tile.Drag.drop()
                                                tile.x = 0; tile.y = 0
                                                card.dragging = false
                                                if (!moved) {
                                                    Hyprland.dispatch("focuswindow address:" + root.addr(slot.modelData))
                                                    root.close()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Numéro du bureau
                        Text {
                            anchors { top: frame.bottom; topMargin: 6; horizontalCenter: frame.horizontalCenter }
                            text: (card.wsId > 5 ? card.wsId - 5 : card.wsId) + "  ·  " + (card.wsId > 5 ? "AOC" : "Samsung")
                                  + (card.ws?.toplevels.values.length ? "" : "  ·  vide")
                            color: card.ws?.active ? root.accent : root.fg
                            font { family: "CaskaydiaCove Nerd Font"; pixelSize: 14; bold: card.ws?.active ?? false }
                        }
                    }
                }
            }

            Text {
                anchors { bottom: parent.bottom; bottomMargin: 40; horizontalCenter: parent.horizontalCenter }
                text: "Glisser une fenêtre : bords = moitié · coins = quart · haut = plein écran · centre = déplacer  ·  Clic pour y aller  ·  Échap pour fermer"
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.6)
                font { family: "CaskaydiaCove Nerd Font"; pixelSize: 13 }
            }
        }
    }
}
