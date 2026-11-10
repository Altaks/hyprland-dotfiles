// Sélecteur de fond d'écran (images, vidéos, diaporama) — inspiré d'elifouts/Dotfiles.
// Ouverture : qs -c wallpicker ipc call wallpicker toggle   (Super+P)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: home + "/.local/bin/"

    property bool shown: false
    property var targetScreen: Quickshell.screens[0]
    property var all: []
    property string filter: "all"   // all | images | videos
    readonly property var items: all.filter(w => filter === "all" || (filter === "videos") === w.video)
    property string slideshow: "off"

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

    FileView {
        id: currentFile
        path: root.home + "/.cache/hypr-wallpaper/current"
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property string current: currentFile.text().trim()

    // --- Index des fonds d'écran ---
    Process {
        id: indexer
        command: [root.bin + "wallpicker-index"]
        onExited: loader.running = true
    }
    Process {
        id: loader
        command: ["cat", root.home + "/.cache/wallpicker/index.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.all = JSON.parse(text) } catch (e) { root.all = [] }
                root.centreOnCurrent()
            }
        }
    }
    Process {
        id: slideStatus
        command: [root.bin + "hypr-slideshow", "status"]
        stdout: StdioCollector { onStreamFinished: root.slideshow = text.trim() }
    }
    Timer { id: slideRefresh; interval: 400; onTriggered: slideStatus.running = true }

    // Ouvre sur l'écran où se trouve la souris.
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
                indexer.running = true
                slideStatus.running = true
            }
        }
    }

    function open() { if (!shown) cursorQuery.running = true }
    function close() { shown = false }
    function toggle() { shown ? close() : open() }

    function centreOnCurrent() {
        const i = items.findIndex(w => w.path === current)
        carousel.currentIndex = i >= 0 ? i : 0
    }
    function setFilter(f) {
        filter = f
        Qt.callLater(centreOnCurrent)
    }
    function apply(w) {
        Quickshell.execDetached([bin + "hypr-wallpaper", w.path])
        close()
    }
    function toggleSlideshow() {
        Quickshell.execDetached([bin + "hypr-slideshow", "toggle", "10"])
        slideRefresh.restart()
    }

    IpcHandler {
        target: "wallpicker"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }

    PanelWindow {
        id: win
        visible: root.shown
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "wallpicker"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: if (visible) keys.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.6)
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Escape: root.close(); break
                case Qt.Key_Left: carousel.decrementCurrentIndex(); break
                case Qt.Key_Right: carousel.incrementCurrentIndex(); break
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (root.items.length) root.apply(root.items[carousel.currentIndex]); break
                case Qt.Key_Tab:
                    root.setFilter(root.filter === "all" ? "images" : root.filter === "images" ? "videos" : "all"); break
                case Qt.Key_S: root.toggleSlideshow(); break
                default: return
                }
                event.accepted = true
            }

            Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: 28

                // --- Onglets + diaporama ---
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    Repeater {
                        model: [["all", "Tous"], ["images", "Images"], ["videos", "Vidéos"]]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: root.filter === modelData[0]
                            width: label.implicitWidth + 32
                            height: 36
                            radius: 18
                            color: active ? root.accent : Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.85)
                            border.width: 2
                            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                            Text {
                                id: label
                                anchors.centerIn: parent
                                text: parent.modelData[1]
                                color: parent.active ? root.bg : root.fg
                                font { family: "CaskaydiaCove Nerd Font"; pixelSize: 14; bold: true }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.setFilter(parent.modelData[0]) }
                        }
                    }

                    Item { width: 20; height: 1 }

                    Rectangle {
                        readonly property bool on: root.slideshow.startsWith("on")
                        width: slideLabel.implicitWidth + 32
                        height: 36
                        radius: 18
                        color: on ? root.accent : Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.85)
                        border.width: 2
                        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                        Text {
                            id: slideLabel
                            anchors.centerIn: parent
                            text: parent.on ? "󰐊  Diaporama (" + root.slideshow.split(" ")[1] + " min)" : "󰐊  Diaporama"
                            color: parent.on ? root.bg : root.fg
                            font { family: "CaskaydiaCove Nerd Font"; pixelSize: 14; bold: true }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.toggleSlideshow() }
                    }
                }

                // --- Carrousel ---
                PathView {
                    id: carousel
                    width: parent.width
                    height: 420
                    model: root.items
                    pathItemCount: Math.min(7, root.items.length)
                    preferredHighlightBegin: 0.5
                    preferredHighlightEnd: 0.5
                    highlightRangeMode: PathView.StrictlyEnforceRange
                    highlightMoveDuration: 280
                    interactive: true

                    path: Path {
                        startX: 0; startY: carousel.height / 2
                        PathAttribute { name: "itemScale"; value: 0.55 }
                        PathAttribute { name: "itemZ"; value: 0 }
                        PathLine { x: carousel.width / 2; y: carousel.height / 2 }
                        PathAttribute { name: "itemScale"; value: 1.0 }
                        PathAttribute { name: "itemZ"; value: 10 }
                        PathLine { x: carousel.width; y: carousel.height / 2 }
                        PathAttribute { name: "itemScale"; value: 0.55 }
                        PathAttribute { name: "itemZ"; value: 0 }
                    }

                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: PathView.isCurrentItem
                        width: 560
                        height: 315
                        scale: PathView.itemScale ?? 1
                        z: PathView.itemZ ?? 0
                        opacity: 0.35 + 0.65 * ((PathView.itemScale ?? 1) - 0.55) / 0.45

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: 16
                            color: root.bg
                            border.width: card.isCurrent ? 3 : 0
                            border.color: root.accent

                            Image {
                                anchors.fill: parent
                                source: "file://" + card.modelData.thumb
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize { width: 640; height: 360 }
                            }
                        }

                        // Badge vidéo
                        Rectangle {
                            visible: card.modelData.video
                            anchors { top: parent.top; right: parent.right; margins: 12 }
                            width: 44; height: 28; radius: 14
                            color: Qt.rgba(0, 0, 0, 0.6)
                            Text {
                                anchors.centerIn: parent
                                text: "󰕧"
                                color: "white"
                                font { family: "CaskaydiaCove Nerd Font"; pixelSize: 16 }
                            }
                        }

                        // Fond d'écran actuel
                        Rectangle {
                            visible: card.modelData.path === root.current
                            anchors { top: parent.top; left: parent.left; margins: 12 }
                            width: 28; height: 28; radius: 14
                            color: root.accent
                            Text {
                                anchors.centerIn: parent
                                text: "󰄬"
                                color: root.bg
                                font { family: "CaskaydiaCove Nerd Font"; pixelSize: 16 }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: card.isCurrent ? root.apply(card.modelData) : carousel.currentIndex = card.index
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.items.length ? root.items[carousel.currentIndex]?.name ?? "" : "Aucun fond d'écran dans ~/Pictures/backgrounds"
                    color: root.fg
                    font { family: "CaskaydiaCove Nerd Font"; pixelSize: 20; bold: true }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "←/→ naviguer  ·  Entrée appliquer  ·  Tab filtrer  ·  S diaporama  ·  Échap fermer"
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.6)
                    font { family: "CaskaydiaCove Nerd Font"; pixelSize: 13 }
                }
            }
        }
    }
}
