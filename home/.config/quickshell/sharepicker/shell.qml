// Sélecteur de partage d'écran façon GNOME (Discord, navigateur…), lancé par ~/.local/bin/qs-share-picker
// pour xdg-desktop-portal-hyprland. Onglets Écran / Fenêtre avec aperçus en direct ;
// clic = choisir, double-clic ou Entrée = partager, Échap = annuler.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string font: "CaskaydiaCove Nerd Font"

    // --- Couleurs Pywal ---
    FileView { id: walFile; path: root.home + "/.cache/wal/colors.json" }
    readonly property var wal: {
        try { return JSON.parse(walFile.text()) } catch (e) { return null }
    }
    readonly property color bg: wal ? wal.special.background : "#161515"
    readonly property color fg: wal ? wal.special.foreground : "#c4c4c4"
    readonly property color accent: wal ? wal.colors.color4 : "#8aadf4"
    readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
    readonly property color surface: Qt.rgba(fg.r, fg.g, fg.b, 0.08)

    // --- Fenêtres partageables, fournies par xdph ---
    // « id[HC>]classe[HT>]titre[HE>]adresse[HA>] » répété ; id = poignée attendue en retour.
    readonly property var windows: (Quickshell.env("XDPH_WINDOW_SHARING_LIST") ?? "").split("[HA>]")
        .filter(e => e.includes("[HC>]"))
        .map(e => {
            const id = e.split("[HC>]")[0]
            const rest = e.split("[HC>]")[1]
            const cls = rest.split("[HT>]")[0]
            const title = rest.split("[HT>]")[1].split("[HE>]")[0]
            const addr = rest.split("[HE>]")[1] ?? ""
            return { id: id, cls: cls, title: title, addr: addr }
        })
    // Toplevel Hyprland correspondant (pour l'aperçu) : adresse en décimal ou en hexadécimal
    function toplevel(w) {
        const tops = Hyprland.toplevels.values
        if (w.addr !== "") {
            const cands = [Number(w.addr), parseInt(w.addr.replace(/^0x/, ""), 16)]
            const t = tops.find(t => cands.includes(parseInt(t.address.replace(/^0x/, ""), 16)))
            if (t) return t
        }
        return tops.find(t => t.lastIpcObject?.class === w.cls && t.title === w.title) ?? null
    }
    // Les applications sont indexées en arrière-plan : la longueur de la liste rend la liaison réactive.
    function icon(cls) {
        const e = DesktopEntries.applications.values.length >= 0 ? DesktopEntries.heuristicLookup(cls) : null
        return Quickshell.iconPath(e?.icon ?? "", true) || Quickshell.iconPath(cls, true)
            || Quickshell.iconPath(cls.toLowerCase(), "application-x-executable")
    }
    Component.onCompleted: Hyprland.refreshToplevels()

    // --- Choix ---
    property string tab: "screen"           // screen | window
    property string selScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)?.name
                               ?? Quickshell.screens[0]?.name ?? ""
    property string selWindow: ""
    property bool remember: Quickshell.env("SHARE_PICKER_TOKEN") === "1"
    readonly property bool canShare: tab === "screen" ? selScreen !== "" : selWindow !== ""

    function share() {
        if (!canShare) return
        const what = tab === "screen" ? "screen:" + selScreen : "window:" + selWindow
        writer.command = ["sh", "-c", 'printf "%s\\n" "$1" > "$SHARE_PICKER_OUT"', "sh",
                          "[SELECTION]" + (remember ? "r" : "") + "/" + what]
        writer.running = true
    }
    Process { id: writer; onExited: Qt.quit() }

    PanelWindow {
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        color: Qt.rgba(0, 0, 0, 0.5)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "sharepicker"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        MouseArea { anchors.fill: parent; onClicked: Qt.quit() }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Qt.quit()
            Keys.onReturnPressed: root.share()
            Keys.onEnterPressed: root.share()
            Keys.onTabPressed: root.tab = root.tab === "screen" ? "window" : "screen"

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 900
                height: 640
                radius: 16
                color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.98)
                border.width: 2
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)

                MouseArea { anchors.fill: parent }

                // En-tête façon GNOME : Annuler · titre · Partager
                Item {
                    id: header
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
                    height: 40

                    HeaderButton {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        label: "Annuler"
                        onClicked: Qt.quit()
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "Partage d'écran"
                        color: root.fg
                        font { family: root.font; pixelSize: 16; bold: true }
                    }
                    HeaderButton {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        label: "Partager"
                        primary: true
                        enabled: root.canShare
                        onClicked: root.share()
                    }
                }

                Text {
                    id: subtitle
                    anchors { top: header.bottom; topMargin: 10; horizontalCenter: parent.horizontalCenter }
                    text: "Choisissez ce que vous souhaitez partager."
                    color: root.dim
                    font { family: root.font; pixelSize: 13 }
                }

                // Onglets Écran / Fenêtre (bouton segmenté)
                Rectangle {
                    id: tabs
                    anchors { top: subtitle.bottom; topMargin: 14; horizontalCenter: parent.horizontalCenter }
                    width: 300; height: 36; radius: 18
                    color: root.surface
                    Row {
                        anchors { fill: parent; margins: 3 }
                        Repeater {
                            model: [{ key: "screen", label: "󰍹  Écran" }, { key: "window", label: "󰖯  Fenêtre" }]
                            Rectangle {
                                required property var modelData
                                width: parent.width / 2; height: parent.height; radius: 15
                                color: root.tab === modelData.key ? root.accent : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    color: root.tab === parent.modelData.key ? root.bg : root.fg
                                    font { family: root.font; pixelSize: 13; bold: root.tab === parent.modelData.key }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.tab = parent.modelData.key
                                }
                            }
                        }
                    }
                }

                // Aperçus
                Flickable {
                    id: grid
                    anchors { top: tabs.bottom; topMargin: 18; left: parent.left; right: parent.right
                              bottom: footer.top; bottomMargin: 12; leftMargin: 24; rightMargin: 24 }
                    contentHeight: flow.implicitHeight
                    clip: true

                    Flow {
                        id: flow
                        width: parent.width
                        spacing: 16
                        readonly property int cols: root.tab === "screen" ? 2 : 3
                        readonly property real tileW: (width - spacing * (cols - 1)) / cols

                        Repeater {
                            model: root.tab === "screen" ? Quickshell.screens : root.windows
                            Tile {
                                required property var modelData
                                width: flow.tileW
                                isScreen: root.tab === "screen"
                                source: isScreen ? modelData : root.toplevel(modelData)?.wayland ?? null
                                label: isScreen ? (modelData.model || modelData.name) + "  ·  " + modelData.width + "×" + modelData.height
                                                : (modelData.title || modelData.cls)
                                iconSource: isScreen ? "" : root.icon(modelData.cls)
                                selected: isScreen ? root.selScreen === modelData.name : root.selWindow === modelData.id
                                onPicked: isScreen ? root.selScreen = modelData.name : root.selWindow = modelData.id
                                onChosen: root.share()
                            }
                        }
                    }

                    Text {
                        visible: root.tab === "window" && root.windows.length === 0
                        anchors.centerIn: parent
                        text: "Aucune fenêtre à partager"
                        color: root.dim
                        font { family: root.font; pixelSize: 14 }
                    }
                }

                // Mémoriser le choix (jeton de restauration)
                Row {
                    id: footer
                    anchors { bottom: parent.bottom; bottomMargin: 18; left: parent.left; leftMargin: 24 }
                    spacing: 10
                    Rectangle {
                        width: 20; height: 20; radius: 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.remember ? root.accent : "transparent"
                        border.width: 2
                        border.color: root.remember ? root.accent : root.dim
                        Text {
                            anchors.centerIn: parent
                            visible: root.remember
                            text: "󰄬"
                            color: root.bg
                            font { family: root.font; pixelSize: 14 }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Mémoriser ce choix pour cette application"
                        color: root.fg
                        font { family: root.font; pixelSize: 13 }
                    }
                    TapHandler { onTapped: root.remember = !root.remember }
                }
            }
        }
    }

    component HeaderButton: Rectangle {
        id: btn
        property string label
        property bool primary: false
        signal clicked
        width: txt.implicitWidth + 32; height: 34; radius: 10
        opacity: enabled ? 1 : 0.4
        color: primary ? (ma.containsMouse ? Qt.lighter(root.accent, 1.1) : root.accent)
                       : (ma.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15) : root.surface)
        Text {
            id: txt
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? root.bg : root.fg
            font { family: root.font; pixelSize: 13; bold: true }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component Tile: Item {
        id: tile
        property var source: null
        property bool isScreen: false
        property string label
        property string iconSource
        property bool selected: false
        signal picked
        signal chosen
        height: thumb.height + 40

        Rectangle {
            id: thumb
            width: parent.width
            height: width * (tile.isScreen ? 9 / 16 : 10 / 16)
            radius: 12
            color: tile.selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                 : ma.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12) : root.surface
            border.width: tile.selected ? 3 : 0
            border.color: root.accent

            ScreencopyView {
                anchors { fill: parent; margins: 10 }
                captureSource: tile.source
                live: true
                constraintSize: Qt.size(width, height)
                visible: hasContent
            }
            // Pas d'aperçu (fenêtre sur un bureau caché pas encore rendue…) : grande icône
            IconImage {
                anchors.centerIn: parent
                visible: !tile.isScreen && tile.source === null
                implicitSize: 64
                source: tile.iconSource
            }
            // Coche de sélection, comme GNOME
            Rectangle {
                visible: tile.selected
                anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                width: 26; height: 26; radius: 13
                color: root.accent
                Text {
                    anchors.centerIn: parent
                    text: "󰄬"
                    color: root.bg
                    font { family: root.font; pixelSize: 16 }
                }
            }
        }

        Row {
            anchors { top: thumb.bottom; topMargin: 10; horizontalCenter: parent.horizontalCenter }
            width: Math.min(implicitWidth, parent.width)
            spacing: 8
            IconImage {
                visible: !tile.isScreen
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 18
                source: tile.iconSource
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, tile.width - 30)
                elide: Text.ElideRight
                text: tile.label
                color: tile.selected ? root.accent : root.fg
                font { family: root.font; pixelSize: 13; bold: tile.selected }
            }
        }

        MouseArea {
            id: ma
            anchors { fill: thumb }
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.picked()
            onDoubleClicked: tile.chosen()
        }
    }
}
