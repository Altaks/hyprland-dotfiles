// Aperçu de la zone d'aimantation pendant un Super+glisser (façon Windows).
// Piloté par ~/.local/bin/hypr-dragsnap :
//   qs -c snapzone ipc call snapzone preview "<écran> <x> <y> <w> <h>"   (coordonnées locales à l'écran ;
//   « show » est réservé par « qs ipc show »)
//   qs -c snapzone ipc call snapzone hide
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property string screenName: ""
    property rect zone: Qt.rect(0, 0, 0, 0)

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
    readonly property color accent: wal ? wal.colors.color4 : "#8aadf4"

    IpcHandler {
        target: "snapzone"
        function preview(spec: string): void {
            const p = spec.split(" ")
            root.zone = Qt.rect(+p[1], +p[2], +p[3], +p[4])
            root.screenName = p[0]
        }
        function hide(): void { root.screenName = "" }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            readonly property bool active: root.screenName === modelData.name
            visible: active || box.opacity > 0
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "snapzone"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}    // ne capte aucun clic

            Rectangle {
                id: box
                x: root.zone.x; y: root.zone.y
                width: root.zone.width; height: root.zone.height
                radius: 10
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                border { width: 2; color: root.accent }
                opacity: panel.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
        }
    }
}
