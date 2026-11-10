// Horloge de bureau façon « Mond Minimal » (DesktopSuite / skin Rainmeter Mond).
// Posée au-dessus du fond d'écran, sous les fenêtres, sur l'écran principal.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root

    // Écran principal (Samsung) ; repli sur le premier écran.
    readonly property var targetScreen: Quickshell.screens.find(s => s.name === "DP-1") ?? Quickshell.screens[0]
    readonly property real s: targetScreen ? targetScreen.height / 1440 * 2.2 : 2.2
    readonly property var fr: Qt.locale("fr_FR")
    // Anurati si elle est installée, sinon Montserrat en très gras.
    readonly property bool hasAnurati: Qt.fontFamilies().indexOf("Anurati") !== -1

    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const d = new Date()
            if (d.getMinutes() !== root.now.getMinutes() || d.getDate() !== root.now.getDate())
                root.now = d
        }
    }

    PanelWindow {
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "desktop-clock"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Ne capte aucun clic : tout passe au bureau.
        mask: Region {}

        Item {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.30
            width: parent.width
            height: col.height

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#99000000"
                shadowBlur: 0.6
                shadowVerticalOffset: 2 * root.s
            }

            Column {
                id: col
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14 * root.s

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "- " + Qt.formatTime(root.now, "HH:mm") + " -"
                    color: "white"
                    opacity: 0.95
                    font { family: "Montserrat"; pixelSize: 15 * root.s; weight: Font.Normal }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.fr.dayName(root.now.getDay(), Locale.LongFormat).toUpperCase()
                    color: "white"
                    font {
                        family: root.hasAnurati ? "Anurati" : "Montserrat"
                        weight: root.hasAnurati ? Font.Normal : Font.Black
                        pixelSize: 38 * root.s
                        letterSpacing: (root.hasAnurati ? 8 : 12) * root.s
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.now.getDate().toString().padStart(2, "0") + " "
                          + root.fr.monthName(root.now.getMonth(), Locale.LongFormat).toUpperCase()
                          + ", " + root.now.getFullYear() + "."
                    color: "white"
                    opacity: 0.92
                    font { family: "Montserrat"; pixelSize: 13 * root.s; weight: Font.Bold; letterSpacing: 1.5 * root.s }
                }
            }
        }
    }
}
