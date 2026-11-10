// Menus déroulants de la barre, façon Réglages rapides de GNOME.
// Ouverture : qs -c controls ipc call controls toggle <audio|devices|calendar|power>
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property string panel: ""            // "" = fermé
    property var targetScreen: Quickshell.screens[0]
    property string pending: ""
    property int mediaX: -1              // bord gauche de la pilule musique (waybar-pill-left)

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
    readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
    readonly property color surface: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
    readonly property string font: "CaskaydiaCove Nerd Font"

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
                root.panel = root.pending
            }
        }
    }
    function toggle(name) {
        if (panel === name) { panel = ""; return }
        pending = name
        cursorQuery.running = true
    }

    IpcHandler {
        target: "controls"
        function toggle(name: string): void { root.toggle(name) }
        function close(): void { root.panel = "" }
        // Panneau musique aligné sur la pilule Waybar (x = son bord gauche, relatif à l'écran)
        function media(x: int): void { root.mediaX = x; root.toggle("media") }
        // Ouvre le tableau de bord sur un onglet : home | weather | news | cyber | agenda | github | updates | perf
        // Un second appel sur le même onglet referme le tableau de bord.
        function dashboard(tab: string): void {
            if (root.panel === "dashboard" && root.dashTab === tab) { root.panel = ""; return }
            root.dashTab = tab
            if (root.panel !== "dashboard") root.toggle("dashboard")
        }
    }

    // --- Son ---
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && !n.isSink
                                                                  && !(n.name ?? "").endsWith(".monitor"))
    // Flux des applications : lecture (isSink) et enregistrement.
    readonly property var playStreams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.isSink)
                                              .sort((a, b) => root.appName(a).localeCompare(root.appName(b)) || a.id - b.id)
    readonly property var recStreams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && !n.isSink)
    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].concat(root.playStreams, root.recStreams) }
    function label(n) { return n ? (n.description || n.nickname || n.name) : "—" }
    // Noms lisibles : Discord s'annonce « WEBRTC VoiceEngine », Vice « gsr-default_output »…
    readonly property var appNames: ({ "Discord": "Discord", "spotify": "Spotify", "java": "Minecraft (Java)",
                                        "gpu-screen-recorder": "Vice (enregistreur)", "zen": "Zen", "zen-bin": "Zen",
                                        "firefox": "Firefox", "mpv": "mpv", "mpvpaper": "Fond d'écran vidéo" })
    function appName(n) {
        const p = n?.properties ?? {}
        const bin = p["application.process.binary"] ?? ""
        return root.appNames[bin] ?? p["application.name"] ?? label(n)
    }
    function appDetail(n) {
        const m = n?.properties?.["media.name"] ?? ""
        return ["", "Playback Stream", "playStream", "recStream", appName(n)].includes(m)
               || m === n?.properties?.["application.name"] ? "" : m
    }
    function appIcon(n) {
        const p = n?.properties ?? {}
        return Quickshell.iconPath(p["application.icon-name"] ?? "", true)
            || Quickshell.iconPath((p["application.process.binary"] ?? "").toLowerCase(), true)
    }

    // --- Lecteur multimédia ---
    // Lecteur choisi à la main dans le panneau, sinon celui qui joue, sinon le premier.
    property var chosenPlayer: null
    readonly property var player: (chosenPlayer && Mpris.players.values.includes(chosenPlayer) ? chosenPlayer : null)
                                  ?? Mpris.players.values.find(p => p.isPlaying && root.isTwitch(p))
                                  ?? Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    // La position MPRIS n'est pas poussée en continu : on la redemande chaque seconde.
    Timer {
        interval: 1000
        repeat: true
        running: (root.panel === "media" || root.panel === "dashboard") && (root.player?.isPlaying ?? false)
        onTriggered: root.player.positionChanged()
    }
    function timeStr(s) {
        s = Math.max(0, Math.floor(s))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    // Twitch tourne dans le navigateur (lecteur MPRIS « firefox ») : reconnu par l'URL de la page.
    function mediaUrl(p) { return p?.metadata?.["xesam:url"] ?? "" }
    function isTwitch(p) { return /^https?:\/\/([a-z]+\.)?twitch\.tv\//.test(mediaUrl(p)) }
    // En direct : chaîne Twitch (pas une VOD /videos/), ou durée « infinie » annoncée par le lecteur
    function isLive(p) {
        if (!p) return false
        if (isTwitch(p)) return !/\/videos\//.test(mediaUrl(p))
        return (p.length ?? 0) > 1e9
    }
    function playerName(p) {
        if (!p) return ""
        if (isTwitch(p)) return "Twitch"
        return p.identity === "Mozilla zen" ? "Zen" : p.identity
    }

    // ===================== Fenêtre =====================
    PanelWindow {
        visible: root.panel !== ""
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "controls"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        // Un clic en dehors du menu le ferme.
        MouseArea { anchors.fill: parent; onClicked: root.panel = "" }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.panel = ""

            Rectangle {
                id: card
                y: 50
                x: root.panel === "calendar" || root.panel === "dashboard" ? (parent.width - width) / 2
                 : root.panel === "media" ? Math.max(10, Math.min(root.mediaX, parent.width - width - 10))
                 : parent.width - width - 10
                width: root.panel === "dashboard" ? 1040 : root.panel === "calendar" ? 360 : root.panel === "media" ? 360 : 380
                height: content.implicitHeight + 32
                radius: 16
                color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.98)
                border.width: 2
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)

                // Les clics dans le menu ne le ferment pas.
                MouseArea { anchors.fill: parent }

                Loader {
                    id: content
                    anchors { fill: parent; margins: 16 }
                    sourceComponent: root.panel === "audio" ? audioPanel
                                   : root.panel === "devices" ? devicesPanel
                                   : root.panel === "calendar" ? calendarPanel
                                   : root.panel === "vitals" ? vitalsPanel
                                   : root.panel === "media" ? mediaPanel
                                   : root.panel === "dashboard" ? dashboardPanel
                                   : root.panel === "power" ? powerPanel : null
                }
            }
        }
    }

    // ===================== Composants communs =====================
    component Title: Text {
        color: root.fg
        font { family: root.font; pixelSize: 15; bold: true }
    }

    component VolumeSlider: Item {
        id: slider
        property var node: null
        property string icon: "󰕾"
        property string mutedIcon: "󰝟"
        readonly property real value: node?.audio ? Math.min(1, node.audio.volume) : 0
        readonly property bool muted: node?.audio?.muted ?? false
        width: parent.width
        height: 36

        Rectangle {
            id: muteBtn
            width: 36; height: 36; radius: 18
            color: slider.muted ? root.surface : root.accent
            Text {
                anchors.centerIn: parent
                text: slider.muted ? slider.mutedIcon : slider.icon
                color: slider.muted ? root.fg : root.bg
                font { family: root.font; pixelSize: 17 }
            }
            MouseArea { anchors.fill: parent; onClicked: if (slider.node?.audio) slider.node.audio.muted = !slider.muted }
        }
        Rectangle {
            id: track
            anchors { left: muteBtn.right; leftMargin: 12; right: pct.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            height: 8; radius: 4
            color: root.surface
            Rectangle {
                width: parent.width * slider.value
                height: parent.height; radius: 4
                color: slider.muted ? root.dim : root.accent
            }
            Rectangle {
                x: parent.width * slider.value - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18; radius: 9
                color: root.fg
            }
            MouseArea {
                anchors { fill: parent; topMargin: -12; bottomMargin: -12 }
                function set(mx) { if (slider.node?.audio) slider.node.audio.volume = Math.max(0, Math.min(1, mx / track.width)) }
                onPressed: m => set(m.x)
                onPositionChanged: m => { if (pressed) set(m.x) }
                onWheel: w => set(track.width * (slider.value + (w.angleDelta.y > 0 ? 0.05 : -0.05)))
            }
        }
        Text {
            id: pct
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 44
            horizontalAlignment: Text.AlignRight
            text: Math.round(slider.value * 100) + " %"
            color: root.dim
            font { family: root.font; pixelSize: 13 }
        }
    }

    component DeviceList: Column {
        id: list
        property var nodes: []
        property var current: null
        property bool sink: true
        width: parent.width
        spacing: 2
        Repeater {
            model: list.nodes
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: modelData === list.current
                width: list.width
                height: 34
                radius: 8
                color: hover.containsMouse ? root.surface : "transparent"
                Text {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: parent.active ? "󰄬" : ""
                    color: root.accent
                    font { family: root.font; pixelSize: 15 }
                }
                Text {
                    anchors { left: parent.left; leftMargin: 34; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: root.label(parent.modelData)
                    elide: Text.ElideRight
                    color: parent.active ? root.fg : root.dim
                    font { family: root.font; pixelSize: 13; bold: parent.active }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (list.sink) Pipewire.preferredDefaultAudioSink = parent.modelData
                        else Pipewire.preferredDefaultAudioSource = parent.modelData
                    }
                }
            }
        }
    }

    // Une application : icône + nom au-dessus de son curseur.
    component AppStream: Column {
        id: app
        property var node: null
        property int dup: 0              // n° d'instance quand plusieurs flux portent le même nom
        property bool rec: false
        width: parent.width
        spacing: 4
        Item {
            width: parent.width
            height: 20
            IconImage {
                id: appIc
                width: 18; height: 18
                anchors.verticalCenter: parent.verticalCenter
                source: root.appIcon(app.node)
                visible: source != ""
            }
            Text {
                anchors { left: appIc.visible ? appIc.right : parent.left; leftMargin: appIc.visible ? 8 : 0
                          right: parent.right; verticalCenter: parent.verticalCenter }
                text: root.appName(app.node) + (app.dup > 1 ? " " + app.dup : "")
                      + (root.appDetail(app.node) ? "  ·  " + root.appDetail(app.node) : "")
                elide: Text.ElideRight
                color: root.fg
                font { family: root.font; pixelSize: 13 }
            }
        }
        VolumeSlider { node: app.node; icon: app.rec ? "󰍬" : "󰕾"; mutedIcon: app.rec ? "󰍭" : "󰝟" }
    }

    // ===================== Son =====================
    // Clic gauche sur le son : mélangeur (volumes généraux + par application).
    Component {
        id: audioPanel
        Column {
            spacing: 12
            Title { width: parent.width; elide: Text.ElideRight; text: "󰓃  " + root.label(Pipewire.defaultAudioSink) }
            VolumeSlider { node: Pipewire.defaultAudioSink }
            Title { width: parent.width; elide: Text.ElideRight; text: "󰍬  " + root.label(Pipewire.defaultAudioSource) }
            VolumeSlider { node: Pipewire.defaultAudioSource; icon: "󰍬"; mutedIcon: "󰍭" }
            Rectangle { width: parent.width; height: 1; color: root.surface }
            Title { text: "󰎆  Applications" }
            Text {
                visible: root.playStreams.length === 0
                text: "Aucune application ne joue de son"
                color: root.dim
                font { family: root.font; pixelSize: 13 }
            }
            Repeater {
                model: root.playStreams
                delegate: AppStream {
                    required property var modelData
                    required property int index
                    node: modelData
                    dup: root.playStreams.filter(n => root.appName(n) === root.appName(modelData)).length > 1
                         ? root.playStreams.slice(0, index).filter(n => root.appName(n) === root.appName(modelData)).length + 1 : 0
                }
            }
            Rectangle { visible: root.recStreams.length > 0; width: parent.width; height: 1; color: root.surface }
            Title { visible: root.recStreams.length > 0; text: "󰑊  Enregistrement" }
            Repeater {
                model: root.recStreams
                delegate: AppStream { required property var modelData; node: modelData; rec: true }
            }
            Text {
                text: "Clic droit sur le son : choisir la sortie et le micro"
                color: root.dim
                font { family: root.font; pixelSize: 11 }
            }
        }
    }

    // Clic droit sur le son : choix des périphériques d'entrée et de sortie.
    Component {
        id: devicesPanel
        Column {
            spacing: 12
            Title { text: "󰓃  Sortie" }
            DeviceList { nodes: root.sinks; current: Pipewire.defaultAudioSink; sink: true }
            Rectangle { width: parent.width; height: 1; color: root.surface }
            Title { text: "󰍬  Micro" }
            DeviceList { nodes: root.sources; current: Pipewire.defaultAudioSource; sink: false }
        }
    }

    // ===================== Calendrier (façon Caelestia) =====================
    // Forme « soleil » de Material 3 (MaterialShape.Sunny) : un cercle festonné.
    component SunnyShape: Shape {
        id: sunny
        property color fill: root.accent
        property int lobes: 8
        property real depth: 0.09
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: sunny.fill
            strokeWidth: -1
            PathPolyline {
                path: {
                    const pts = [], n = 160, c = sunny.width / 2, r = sunny.width / 2 / (1 + sunny.depth)
                    for (let i = 0; i <= n; i++) {
                        const a = i / n * 2 * Math.PI
                        const rr = r * (1 + sunny.depth * Math.cos(sunny.lobes * a))
                        pts.push(Qt.point(c + rr * Math.cos(a), c + rr * Math.sin(a)))
                    }
                    return pts
                }
            }
        }
    }

    Component {
        id: calendarPanel
        Item {
            id: cal
            implicitHeight: col.implicitHeight
            property date viewDate: new Date()
            readonly property int month: viewDate.getMonth()
            readonly property int year: viewDate.getFullYear()
            readonly property var fr: Qt.locale("fr_FR")
            readonly property color weekend: root.wal ? root.wal.colors.color5 : "#f5bde6"
            readonly property bool isCurrent: {
                const n = new Date()
                return month === n.getMonth() && year === n.getFullYear()
            }

            // Glissement + fondu à chaque changement de mois
            property real slide: 0
            property real fade: 1
            property date prev: viewDate
            function shift(delta) {
                const d = new Date(year, month + delta, 1)
                slideIn(d > viewDate ? 1 : -1)
                viewDate = d
            }
            function today() {
                if (isCurrent) return
                const d = new Date()
                slideIn(d > viewDate ? 1 : -1)
                viewDate = d
            }
            function slideIn(dir) {
                anim.stop()
                slide = 24 * dir
                fade = 0
                anim.start()
            }
            ParallelAnimation {
                id: anim
                NumberAnimation { target: cal; property: "slide"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                NumberAnimation { target: cal; property: "fade"; to: 1; duration: 220; easing.type: Easing.OutQuad }
            }

            // Molette = changer de mois ; clic du milieu = revenir à aujourd'hui
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton
                onClicked: cal.today()
                onWheel: w => cal.shift(w.angleDelta.y > 0 ? -1 : 1)
            }

            Column {
                id: col
                width: parent.width
                spacing: 6

                // Navigation : ‹  Octobre 2026  ›
                Item {
                    width: parent.width
                    height: 40
                    Rectangle {
                        id: prevBtn
                        width: 36; height: 36; radius: 18
                        anchors.verticalCenter: parent.verticalCenter
                        color: prevMa.containsMouse ? root.surface : "transparent"
                        Text { anchors.centerIn: parent; text: "󰅁"; color: root.fg; font { family: root.font; pixelSize: 18; bold: true } }
                        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; onClicked: cal.shift(-1) }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: title.implicitWidth + 32
                        height: 34
                        radius: titleMa.pressed ? 8 : height / 2
                        Behavior on radius { NumberAnimation { duration: 150 } }
                        color: titleMa.containsMouse && !cal.isCurrent ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : "transparent"
                        Text {
                            id: title
                            anchors.centerIn: parent
                            opacity: cal.fade
                            transform: Translate { x: cal.slide }
                            text: {
                                const m = cal.fr.monthName(cal.month, Locale.LongFormat)
                                return m.charAt(0).toUpperCase() + m.slice(1) + " " + cal.year
                            }
                            color: root.accent
                            font { family: root.font; pixelSize: 16; bold: true }
                        }
                        MouseArea {
                            id: titleMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: cal.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: cal.today()
                        }
                    }
                    Rectangle {
                        width: 36; height: 36; radius: 18
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        color: nextMa.containsMouse ? root.surface : "transparent"
                        Text { anchors.centerIn: parent; text: "󰅂"; color: root.fg; font { family: root.font; pixelSize: 18; bold: true } }
                        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; onClicked: cal.shift(1) }
                    }
                }

                // Jours de la semaine (week-end dans la couleur secondaire)
                DayOfWeekRow {
                    width: parent.width
                    locale: cal.fr
                    delegate: Text {
                        required property var model
                        horizontalAlignment: Text.AlignHCenter
                        text: model.shortName.replace(".", "")
                        color: (model.day === 0 || model.day === 6) ? cal.weekend : root.fg
                        font { family: root.font; pixelSize: 12; weight: Font.Medium }
                    }
                }

                MonthGrid {
                    id: grid
                    width: parent.width
                    height: 6 * 44
                    month: cal.month
                    year: cal.year
                    locale: cal.fr
                    spacing: 3
                    opacity: cal.fade
                    transform: Translate { x: cal.slide }

                    delegate: Item {
                        id: day
                        required property var model
                        readonly property bool weekend: model.date.getDay() === 0 || model.date.getDay() === 6
                        implicitHeight: 40

                        // Aujourd'hui : posé sur la forme « soleil »
                        SunnyShape {
                            visible: day.model.today
                            anchors.centerIn: parent
                            width: 40; height: 40
                        }
                        Text {
                            anchors.centerIn: parent
                            text: day.model.day
                            color: day.model.today ? root.bg : day.weekend ? cal.weekend : root.dim
                            opacity: day.model.today || day.model.month === cal.month ? 1 : 0.4
                            font { family: root.font; pixelSize: 13; bold: day.model.today }
                        }
                    }
                }
            }
        }
    }

    // ===================== Lecteur de musique =====================
    // Pastille « EN DIRECT » (rouge Twitch)
    component LiveBadge: Rectangle {
        width: liveText.implicitWidth + 16
        height: 20
        radius: 10
        color: "#eb0400"
        Text {
            id: liveText
            anchors.centerIn: parent
            text: "● EN DIRECT"
            color: "white"
            font { family: root.font; pixelSize: 10; bold: true; letterSpacing: 0.5 }
        }
    }

    component IconButton: Rectangle {
        id: ib
        property string icon
        property bool active: false
        property bool big: false
        property bool enabledState: true
        signal clicked()
        width: big ? 56 : 40
        height: width
        radius: width / 2
        color: big ? root.accent : (ibHover.containsMouse ? root.surface : "transparent")
        opacity: enabledState ? 1 : 0.35
        Text {
            anchors.centerIn: parent
            text: ib.icon
            color: ib.big ? root.bg : (ib.active ? root.accent : root.fg)
            font { family: root.font; pixelSize: ib.big ? 26 : 19 }
        }
        MouseArea {
            id: ibHover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: if (ib.enabledState) ib.clicked()
        }
    }

    Component {
        id: mediaPanel
        Column {
            id: media
            spacing: 12
            readonly property var p: root.player

            Text {
                visible: !media.p
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Aucune musique en cours"
                color: root.dim
                font { family: root.font; pixelSize: 14 }
            }

            // Choix du lecteur quand plusieurs tournent
            Row {
                visible: Mpris.players.values.length > 1
                spacing: 6
                Repeater {
                    model: Mpris.players.values
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: modelData === media.p
                        width: plabel.implicitWidth + 20
                        height: 26
                        radius: 13
                        color: sel ? root.accent : root.surface
                        Text {
                            id: plabel
                            anchors.centerIn: parent
                            text: root.playerName(parent.modelData)
                            color: parent.sel ? root.bg : root.fg
                            font { family: root.font; pixelSize: 12; bold: parent.sel }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.chosenPlayer = parent.modelData }
                    }
                }
            }

            // Pochette
            Rectangle {
                visible: !!media.p
                width: parent.width
                height: width
                radius: 14
                color: root.surface
                clip: true
                Image {
                    anchors.fill: parent
                    source: media.p?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: !(media.p?.trackArtUrl)
                    text: "󰝚"
                    color: root.dim
                    font { family: root.font; pixelSize: 64 }
                }
            }

            // Titre / artiste / album
            Column {
                visible: !!media.p
                width: parent.width
                spacing: 2
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: media.p?.trackTitle || media.p?.identity || ""
                    color: root.fg
                    font { family: root.font; pixelSize: 16; bold: true }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: media.p?.trackArtist ?? ""
                    color: root.accent
                    font { family: root.font; pixelSize: 13 }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: media.p?.trackAlbum ?? ""
                    color: root.dim
                    font { family: root.font; pixelSize: 12 }
                }
                Item { visible: root.isLive(media.p); width: 1; height: 4 }
                LiveBadge { visible: root.isLive(media.p) }
            }

            // Progression (cliquable si le lecteur sait avancer)
            Column {
                visible: !!media.p && (media.p.lengthSupported ?? false) && media.p.length > 0 && !root.isLive(media.p)
                width: parent.width
                spacing: 4
                Item {
                    width: parent.width
                    height: 14
                    Rectangle {
                        id: bar
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6; radius: 3
                        color: root.surface
                        Rectangle {
                            width: media.p ? parent.width * Math.min(1, media.p.position / Math.max(1, media.p.length)) : 0
                            height: parent.height; radius: 3
                            color: root.accent
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: media.p?.canSeek ?? false
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: m => media.p.position = media.p.length * m.x / width
                    }
                }
                Item {
                    width: parent.width
                    height: 16
                    Text {
                        text: root.timeStr(media.p?.position ?? 0)
                        color: root.dim
                        font { family: root.font; pixelSize: 11 }
                    }
                    Text {
                        anchors.right: parent.right
                        text: root.timeStr(media.p?.length ?? 0)
                        color: root.dim
                        font { family: root.font; pixelSize: 11 }
                    }
                }
            }

            // Contrôles
            Row {
                visible: !!media.p
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "󰒟"
                    active: media.p?.shuffle ?? false
                    enabledState: media.p?.shuffleSupported ?? false
                    onClicked: media.p.shuffle = !media.p.shuffle
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "󰒮"
                    enabledState: media.p?.canGoPrevious ?? false
                    onClicked: media.p.previous()
                }
                IconButton {
                    big: true
                    icon: media.p?.isPlaying ? "󰏤" : "󰐊"
                    enabledState: media.p?.canTogglePlaying ?? false
                    onClicked: media.p.togglePlaying()
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "󰒭"
                    enabledState: media.p?.canGoNext ?? false
                    onClicked: media.p.next()
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    // Aucune → playlist → titre
                    icon: media.p?.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                    active: (media.p?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
                    enabledState: media.p?.loopSupported ?? false
                    onClicked: media.p.loopState = media.p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                                 : media.p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track
                                                 : MprisLoopState.None
                }
            }

            // Ouvrir l'application
            Text {
                visible: media.p?.canRaise ?? false
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Ouvrir " + root.playerName(media.p)
                color: root.dim
                font { family: root.font; pixelSize: 12; underline: openMa.containsMouse }
                MouseArea {
                    id: openMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { media.p.raise(); root.panel = "" }
                }
            }
        }
    }

    // ===================== Tableau de bord (façon Caelestia) =====================
    // Préchargement : toutes les données du tableau de bord sont récupérées ~5 s après le lancement
    // (réseau prêt) puis rafraîchies en arrière-plan à leur rythme, pour qu'ouvrir un onglet soit instantané.
    property bool bgReady: false
    Timer {
        interval: 5000
        running: true
        onTriggered: { root.bgReady = true; if (!naolibProc.running) naolibProc.running = true }
    }
    property string dashTab: "home"          // home | weather | news | cyber | agenda | github | updates | perf
    property var weather: null
    Process {
        id: weatherProc
        command: [root.home + "/.local/bin/weather-fetch"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.weather = JSON.parse(text) } catch (e) {} }
        }
    }
    // Météo relue à l'ouverture puis toutes les 15 min (le script garde un cache).
    Timer {
        interval: 900000
        repeat: true
        triggeredOnStart: true
        running: root.bgReady   // préchargé au démarrage, rafraîchi en arrière-plan
        onTriggered: if (!weatherProc.running) weatherProc.running = true
    }
    // Carte météo (~/.local/bin/weather-map-fetch : radar 5 min, grille de prévisions 1 h), lue sur l'onglet Météo
    property var weatherMap: null
    // classes de l'indice européen de qualité de l'air (EEA)
    function aqiLabel(v) {
        return v < 20 ? "Bonne" : v < 40 ? "Moyenne" : v < 60 ? "Dégradée" : v < 80 ? "Mauvaise" : v < 100 ? "Très mauvaise" : "Extrêmement mauvaise"
    }
    property bool weatherMapFull: false
    Process {
        id: weatherMapProc
        command: [root.home + "/.local/bin/weather-map-fetch"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.weatherMap = JSON.parse(text) } catch (e) {} }
        }
    }
    Timer {
        interval: 300000
        repeat: true
        triggeredOnStart: true
        running: root.bgReady   // préchargé au démarrage, rafraîchi en arrière-plan
        onTriggered: if (!weatherMapProc.running) weatherMapProc.running = true
    }
    // Actualités (~/.local/bin/news-fetch : France 3 Nantes / franceinfo + Le Monde, cache 15 min)
    property var news: null
    Process {
        id: newsProc
        command: [root.home + "/.local/bin/news-fetch"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.news = JSON.parse(text) } catch (e) {} }
        }
    }
    Timer {
        interval: 900000
        repeat: true
        triggeredOnStart: true
        running: root.bgReady   // préchargé au démarrage, rafraîchi en arrière-plan
        onTriggered: if (!newsProc.running) newsProc.running = true
    }
    // GitHub (~/.local/bin/github-fetch : gh api, cache 5 min ; --force au clic sur 󰑐)
    property var gh: null
    property string ghList: "prs"            // prs | reviews | assigned | issues
    property bool ghForce: false
    Process {
        id: ghProc
        command: [root.home + "/.local/bin/github-fetch"].concat(root.ghForce ? ["--force"] : [])
        stdout: StdioCollector {
            onStreamFinished: { try { root.gh = JSON.parse(text) } catch (e) {} root.ghForce = false }
        }
    }
    Timer {
        interval: 300000
        repeat: true
        triggeredOnStart: true
        running: root.bgReady   // préchargé au démarrage, rafraîchi en arrière-plan
        onTriggered: if (!ghProc.running) ghProc.running = true
    }
    // Cyber (~/.local/bin/cyber-fetch : actus, CERT-FR, CVE NVD + KEV + EPSS, cache 1 h)
    property var cyber: null
    property string cyberNews: "news"        // news | certfr
    property string cyberCve: "cves"         // cves | kev | watch
    Process {
        id: cyberProc
        command: [root.home + "/.local/bin/cyber-fetch"]
        stdout: StdioCollector { onStreamFinished: { try { root.cyber = JSON.parse(text) } catch (e) {} } }
    }
    Timer {
        interval: 3600000
        repeat: true
        triggeredOnStart: true
        running: root.bgReady   // préchargé au démarrage, rafraîchi en arrière-plan
        onTriggered: if (!cyberProc.running) cyberProc.running = true
    }
    function cvssColor(score) {
        return score >= 9 ? (root.wal ? root.wal.colors.color1 : "#ed8796")
             : score >= 7 ? (root.wal ? root.wal.colors.color3 : "#eed49f")
             : root.dim
    }

    // Agenda (~/.local/bin/agenda-fetch : adresses iCal de ~/.config/quickshell/agenda.json, cache 10 min)
    property var agenda: null
    Process {
        id: agendaProc
        command: [root.home + "/.local/bin/agenda-fetch"]
        stdout: StdioCollector { onStreamFinished: { try { root.agenda = JSON.parse(text) } catch (e) {} } }
    }
    Timer {
        interval: 600000
        repeat: true
        triggeredOnStart: true
        running: root.bgReady   // préchargé au démarrage, rafraîchi en arrière-plan
        onTriggered: if (!agendaProc.running) agendaProc.running = true
    }
    // Événements regroupés par jour : [{day: Date, events: [...]}]
    readonly property var agendaDays: {
        const out = []
        for (const e of root.agenda?.events ?? []) {
            const day = e.start * 1000 < Date.now() ? new Date() : new Date(e.start * 1000)
            day.setHours(0, 0, 0, 0)
            const last = out[out.length - 1]
            if (last && last.day.getTime() === day.getTime()) last.events.push(e)
            else out.push({ day: day, events: [e] })
        }
        return out
    }
    function agendaColor(e) {
        if (e.color) return e.color
        const names = (root.agenda?.calendars ?? []).map(c => c.name)
        const pal = root.wal ? [root.wal.colors.color4, root.wal.colors.color5, root.wal.colors.color2, root.wal.colors.color3, root.wal.colors.color6] : ["#8aadf4"]
        return pal[Math.max(0, names.indexOf(e.calendar)) % pal.length]
    }
    function dayLabel(d) {
        const t = new Date(); t.setHours(0, 0, 0, 0)
        const diff = Math.round((d.getTime() - t.getTime()) / 86400000)
        const s = d.toLocaleDateString(Qt.locale("fr_FR"), "dddd d MMMM")
        return (diff === 0 ? "Aujourd'hui · " : diff === 1 ? "Demain · " : "") + s.charAt(0).toUpperCase() + s.slice(1)
    }
    function hm(ts) { return new Date(ts * 1000).toLocaleTimeString(Qt.locale("fr_FR"), "HH:mm") }

    // Sorties à Nantes (~/.local/bin/events-fetch : open data Nantes Métropole, cache 1 h)
    property var events: null
    property string evWhen: "today"          // today | tomorrow | weekend | week | later (3 mois)
    property string evCat: "all"
    property bool evFree: false
    property string evQuery: ""              // barre de recherche (titre, lieu, ville, catégories, description)
    readonly property var evCategories: [["all", "Tout"], ["convention", "Conventions"], ["salon", "Salons"], ["music", "Concerts"],
                                         ["stage", "Scène"], ["cine", "Ciné"], ["expo", "Expos · visites"], ["talk", "Conférences"],
                                         ["workshop", "Ateliers"], ["read", "Lecture"], ["party", "Fêtes"], ["market", "Marchés"],
                                         ["games", "Jeux"], ["sport", "Sport"], ["tech", "Tech"], ["meetup", "Meetups"]]
    readonly property var evCatTypes: ({
        convention: ["Convention", "Pop culture"], salon: ["Salon"],
        music: ["Concert - Musique"], games: ["Jeux - Jeux vidéo", "Convention"],
        party: ["Fête - Festival", "Danse - Performance - Bal", "Défilé - Parade - Arts de la rue"],
        market: ["Marché - Vide-greniers - Brocante"],
        stage: ["Théâtre - Humour", "Cirque - Magie - Marionnettes", "Danse - Performance - Bal", "Spectacle"],
        cine: ["Projection"], expo: ["Exposition", "Visite - Balade"],
        talk: ["Conférence - Débat - Réunion publique", "Rencontre - Forum"],
        workshop: ["Stage - Atelier - Activité à partager"], read: ["Contes - Lecture - Poésie"],
        sport: ["Evènement sportif"], tech: ["Tech"], meetup: ["Meetup"]
    })
    function evNorm(s) {
        s = String(s ?? "").toLowerCase()
        try { s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "") } catch (e) {}
        return s
    }
    Process {
        id: eventsProc
        command: [root.home + "/.local/bin/events-fetch"]
        stdout: StdioCollector { onStreamFinished: { try { root.events = JSON.parse(text) } catch (e) {} } }
    }
    Timer {
        interval: 3600000
        repeat: true
        triggeredOnStart: true
        running: root.bgReady   // préchargé au démarrage, rafraîchi en arrière-plan
        onTriggered: if (!eventsProc.running) eventsProc.running = true
    }
    readonly property var eventsFiltered: {
        const d0 = new Date(); d0.setHours(0, 0, 0, 0)
        const iso = d => Qt.formatDate(d, "yyyy-MM-dd")
        const day = n => iso(new Date(d0.getTime() + n * 86400000))
        // week-end = samedi et dimanche à venir (aujourd'hui inclus si on y est)
        const toSat = (6 - d0.getDay() + 7) % 7, wk = d0.getDay() === 0 ? [day(0)] : [day(toSat), day(toSat + 1)]
        // salons et conventions durent plusieurs jours : « until » = dernier jour
        const on = (e, d) => e.date <= d && d <= (e.until || e.date)
        const words = root.evNorm(root.evQuery).split(/\s+/).filter(w => w)
        return (root.events?.events ?? []).filter(e =>
            (root.evWhen === "today" ? on(e, day(0)) : root.evWhen === "tomorrow" ? on(e, day(1))
             : root.evWhen === "weekend" ? wk.some(d => on(e, d)) : root.evWhen === "week" ? e.date <= day(7) : true)
            && (!root.evFree || e.free)
            && (root.evCat === "all" || e.types.some(t => root.evCatTypes[root.evCat].includes(t)))
            && (!words.length || (hay => words.every(w => hay.includes(w)))(root.evNorm(
                   [e.title, e.place, e.city, e.group, e.desc].concat(e.types).join(" ")))))
    }
    function evDur(min) { return min < 60 ? min + " min" : Math.floor(min / 60) + " h " + String(min % 60).padStart(2, "0") }
    function evWhenStr(e) {
        const d = new Date(e.date + "T12:00:00"), t = new Date(); t.setHours(12, 0, 0, 0)
        const diff = Math.round((d - t) / 86400000)
        const fmt = x => x.toLocaleDateString(Qt.locale("fr_FR"), "ddd d MMM")
        if (e.until) {   // plusieurs jours : « Du sam 14 nov au dim 15 nov » / « En cours · jusqu'au … »
            const u = new Date(e.until + "T12:00:00")
            return (diff <= 0 ? "En cours · jusqu'au " + fmt(u) : "Du " + fmt(d) + " au " + fmt(u))
        }
        const day = diff === 0 ? "Aujourd'hui" : diff === 1 ? "Demain" : fmt(d)
        return day + (e.start && e.start !== "00:00" ? " · " + e.start.replace(":", "h") + (e.end && e.end !== e.start ? " – " + e.end.replace(":", "h") : "") : "")
    }

    // Nantes : transports Naolib (~/.local/bin/naolib-fetch, toutes les 30 s), carte, itinéraires Google
    property var naolib: null
    Process {
        id: naolibProc
        command: [root.home + "/.local/bin/naolib-fetch"]
        stdout: StdioCollector { onStreamFinished: { try { root.naolib = JSON.parse(text) } catch (e) {} } }
    }
    Timer {
        interval: 30000
        repeat: true
        triggeredOnStart: true
        running: root.panel === "dashboard" && root.dashTab === "nantes"
        onTriggered: if (!naolibProc.running) naolibProc.running = true
    }
    // Fond de carte + tracés (naolib-build map) : lu une fois
    FileView { id: naoMapFile; path: root.home + "/.cache/dashboard-naolib/map.json"; watchChanges: true; onFileChanged: reload() }
    readonly property var naoMap: { try { return JSON.parse(naoMapFile.text()) } catch (e) { return null } }
    property var route: null
    property int routeSel: 0
    property string routeMode: "transit"
    Process {
        id: routeProc
        stdout: StdioCollector { onStreamFinished: { try { root.route = JSON.parse(text); root.routeSel = 0 } catch (e) {} } }
    }
    function findRoute(from, to) {
        if (!to.trim() || routeProc.running) return
        routeProc.command = [root.home + "/.local/bin/route-fetch", from, to, root.routeMode]
        routeProc.running = true
    }
    function rgba(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")" }
    function durStr(s) {
        const m = Math.round(s / 60)
        return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + String(m % 60).padStart(2, "0")
    }

    // Mises à jour (~/.local/bin/updates-fetch, cache 30 min ; installation via sys-update dans Ptyxis)
    property var updates: null
    readonly property int updCount: (root.updates?.sources ?? []).reduce((n, s) => n + s.count, 0)
    Process {
        id: updProc
        property bool force: false
        command: [root.home + "/.local/bin/updates-fetch"].concat(force ? ["--force"] : [])
        stdout: StdioCollector { onStreamFinished: { try { root.updates = JSON.parse(text) } catch (e) {} updProc.force = false } }
    }
    Timer {
        interval: 1800000
        repeat: true
        triggeredOnStart: true
        running: root.bgReady   // préchargé au démarrage, rafraîchi en arrière-plan
        onTriggered: if (!updProc.running) updProc.running = true
    }
    // Temps d'écran (~/.local/bin/screentime-fetch : ActivityWatch/awatcher → résumé par catégorie, cumul à vie)
    property var screen: null
    readonly property var stCats: {
        const m = {}
        for (const c of (root.screen?.categories ?? [])) m[c.id] = c
        return m
    }
    readonly property var stOrder: (root.screen?.categories ?? []).map(c => c.id)
    function stColor(id) { return root.stCats[id]?.color ?? root.dim }
    function stName(id) { return root.stCats[id]?.name ?? id }
    function stLong(s) {
        const m = Math.floor(s / 60), h = Math.floor(m / 60)
        return h ? h.toLocaleString(Qt.locale("fr_FR"), "f", 0) + " h " + String(m % 60).padStart(2, "0") : m + " min"
    }
    function stAppIcon(cls) {
        const e = DesktopEntries.heuristicLookup(cls)
        return (e && e.icon) ? Quickshell.iconPath(e.icon, true) : Quickshell.iconPath((cls ?? "").toLowerCase(), true)
    }
    Process {
        id: stProc
        command: [root.home + "/.local/bin/screentime-fetch"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); if (!d.error) root.screen = d } catch (e) {} } }
    }
    Timer {
        // 1 min quand l'onglet est ouvert, sinon 5 min en arrière-plan
        interval: root.panel === "dashboard" && root.dashTab === "screen" ? 60000 : 300000
        repeat: true
        triggeredOnStart: true
        running: root.bgReady
        onTriggered: if (!stProc.running) stProc.running = true
    }

    function runUpdate(targets) {
        // term-run : Ptyxis avec bus D-Bus de session garanti (sinon rien ne s'ouvre si qs a perdu son env)
        Quickshell.execDetached([root.home + "/.local/bin/term-run", root.home + "/.local/bin/sys-update " + targets.join(" ")])
        root.panel = ""
    }

    function ghRefresh() { if (!ghProc.running) { root.ghForce = true; ghProc.running = true } }
    function money(x) { return (x ?? 0).toFixed(2).replace(".", ",") + " $" }
    function openUrl(url) { Quickshell.execDetached(["xdg-open", url]); root.panel = "" }
    function agoStr(ts) {
        const m = Math.max(0, Math.floor((Date.now() / 1000 - ts) / 60))
        if (m < 60) return m + " min"
        if (m < 1440) return Math.floor(m / 60) + " h"
        return Math.floor(m / 1440) + " j"
    }
    FileView { id: osRelease; path: "/etc/os-release" }
    readonly property string osName: (osRelease.text().match(/^PRETTY_NAME="?([^"\n]*)"?/m) ?? [, "Linux"])[1]
    function uptimeStr(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return (d ? d + " j " : "") + (h ? h + " h " : "") + m + " min"
    }

    component DashCard: Rectangle {
        radius: 22
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
    }

    // Jauge verticale (carte Ressources)
    component VBar: Column {
        id: vb
        property string icon
        property real value: 0
        property string label
        spacing: 8
        width: 26
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(vb.value * 100)
            color: root.dim
            font { family: root.font; pixelSize: 11 }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 14
            height: 250
            radius: 7
            color: root.surface
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: parent.height * Math.max(0.04, Math.min(1, vb.value))
                radius: 7
                color: vb.value > 0.85 ? (root.wal ? root.wal.colors.color1 : "red") : root.accent
                Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: vb.icon
            color: root.accent
            font { family: root.font; pixelSize: 17 }
        }
    }

    Component {
        id: dashboardPanel
        Column {
            id: dash
            spacing: 14
            property date now: new Date()
            Timer { interval: 1000; repeat: true; running: true; onTriggered: dash.now = new Date() }
            readonly property var s: root.stats
            readonly property var w: root.weather
            readonly property var p: root.player

            // --- Onglets ---
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Repeater {
                    model: [["home", "󰕮  Accueil"], ["weather", "󰖐  Météo"], ["news", "󰎕  Actualités"], ["cyber", "󰒃  Cyber"], ["agenda", "󰃭  Agenda"], ["nantes", "󰍎  Nantes"],
                            ["github", "󰊤  GitHub"], ["updates", "󰚰  Mises à jour" + (root.updCount ? " " + root.updCount : "")], ["screen", "󰔛  Écran"], ["perf", "󰓅  Performances"]]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: root.dashTab === modelData[0]
                        width: tl.implicitWidth + 20
                        height: 36
                        radius: 18
                        color: sel ? root.accent : tabMa.containsMouse ? root.surface : "transparent"
                        Text {
                            id: tl
                            anchors.centerIn: parent
                            text: parent.modelData[1]
                            color: parent.sel ? root.bg : root.fg
                            font { family: root.font; pixelSize: 12; bold: parent.sel }
                        }
                        MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.dashTab = parent.modelData[0] }
                    }
                }
            }

            // ============ Onglet : Tableau de bord ============
            Row {
                visible: root.dashTab === "home"
                spacing: 12

                Column {
                    spacing: 12

                    Row {
                        spacing: 12

                        // Profil
                        DashCard {
                            width: 420; height: 160
                            Rectangle {
                                id: avatarFrame
                                anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                                width: 112; height: 112; radius: 56
                                color: root.surface
                                ClippingRectangle {
                                    anchors.fill: parent
                                    radius: 56
                                    color: "transparent"
                                    Image {
                                        anchors.fill: parent
                                        source: "file://" + root.home + "/.face"
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize { width: 224; height: 224 }
                                        asynchronous: true
                                    }
                                }
                            }
                            Column {
                                anchors { left: avatarFrame.right; leftMargin: 20; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                spacing: 6
                                Text {
                                    text: (dash.now.getHours() < 18 && dash.now.getHours() >= 5 ? "Bonjour" : "Bonsoir") + ", " + Quickshell.env("USER")
                                    color: root.fg
                                    font { family: root.font; pixelSize: 19; bold: true }
                                }
                                Text { text: "󰕈  " + root.osName; color: root.dim; font { family: root.font; pixelSize: 13 } }
                                Text {
                                    text: "󰔟  Allumé depuis " + (dash.s ? root.uptimeStr(dash.s.uptime) : "…")
                                    color: root.dim
                                    font { family: root.font; pixelSize: 13 }
                                }
                                // Prochain événement de l'agenda (clic = onglet Agenda)
                                Column {
                                    readonly property var ev: (root.agenda?.events ?? []).find(e => e.end * 1000 > dash.now.getTime()) ?? null
                                    width: parent.width
                                    topPadding: 4
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: "󰃭  " + (parent.ev ? parent.ev.title : "Rien de prévu")
                                        color: parent.ev ? root.accent : root.dim
                                        font { family: root.font; pixelSize: 13; bold: !!parent.ev }
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        visible: !!parent.ev
                                        text: {
                                            const e = parent.ev
                                            if (!e) return ""
                                            const d = new Date(e.start * 1000), t = new Date(dash.now); t.setHours(0, 0, 0, 0)
                                            const s = new Date(d); s.setHours(0, 0, 0, 0)
                                            const diff = Math.round((s - t) / 86400000)
                                            const day = e.start * 1000 <= dash.now.getTime() ? "En cours" : diff === 0 ? "Aujourd'hui" : diff === 1 ? "Demain"
                                                      : d.toLocaleDateString(Qt.locale("fr_FR"), "dddd d MMM")
                                            return "     " + day + (e.allDay ? "" : " · " + root.hm(e.start))
                                        }
                                        color: root.dim
                                        font { family: root.font; pixelSize: 12 }
                                    }
                                    TapHandler { onTapped: root.dashTab = "agenda" }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }

                        // Météo (résumé)
                        DashCard {
                            width: 260; height: 160
                            MouseArea { anchors.fill: parent; onClicked: root.dashTab = "weather"; cursorShape: Qt.PointingHandCursor }
                            Row {
                                anchors.centerIn: parent
                                spacing: 16
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: dash.w?.icon ?? "󰖐"
                                    color: root.accent
                                    font { family: root.font; pixelSize: 58 }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: dash.w?.temp != null ? dash.w.temp + "°C" : "—"
                                        color: root.fg
                                        font { family: root.font; pixelSize: 30; bold: true }
                                    }
                                    Text {
                                        text: dash.w?.desc ?? (dash.w?.error ?? "Chargement…")
                                        color: root.dim
                                        font { family: root.font; pixelSize: 12 }
                                    }
                                    Text {
                                        visible: !!dash.w?.name
                                        text: (dash.w?.name ?? "") + "  ·  " + (dash.w?.min ?? "") + "° / " + (dash.w?.max ?? "") + "°"
                                        color: root.dim
                                        font { family: root.font; pixelSize: 12 }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        spacing: 12

                        // Grande horloge verticale
                        DashCard {
                            width: 110; height: 372
                            Column {
                                anchors.centerIn: parent
                                spacing: -6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.formatTime(dash.now, "HH")
                                    color: root.fg
                                    font { family: "Montserrat"; pixelSize: 46; weight: Font.DemiBold }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "•••"
                                    color: root.accent
                                    font { family: "Montserrat"; pixelSize: 36 }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.formatTime(dash.now, "mm")
                                    color: root.fg
                                    font { family: "Montserrat"; pixelSize: 46; weight: Font.DemiBold }
                                }
                            }
                        }

                        // Calendrier (le même que le menu Calendrier)
                        DashCard {
                            width: 380; height: 372
                            Loader {
                                anchors { fill: parent; margins: 14 }
                                sourceComponent: calendarPanel
                            }
                        }

                        // Ressources
                        DashCard {
                            width: 178; height: 372
                            MouseArea { anchors.fill: parent; onClicked: root.dashTab = "perf"; cursorShape: Qt.PointingHandCursor }
                            Row {
                                anchors.centerIn: parent
                                spacing: 14
                                VBar { icon: "󰻠"; value: dash.s ? dash.s.cpu.usage / 100 : 0 }
                                VBar { icon: "󰍛"; value: dash.s ? dash.s.mem.used / dash.s.mem.total : 0 }
                                VBar { icon: "󰢮"; value: dash.s?.gpu ? dash.s.gpu.usage / 100 : 0 }
                                VBar { icon: "󰋊"; value: dash.s ? dash.s.disk.used / dash.s.disk.total : 0 }
                            }
                        }
                    }
                }

                // Lecteur
                DashCard {
                    width: 300; height: 544
                    Column {
                        anchors { fill: parent; margins: 22 }
                        spacing: 14

                        Rectangle {
                            width: parent.width; height: width
                            radius: 26
                            color: root.surface
                            ClippingRectangle {
                                anchors.fill: parent
                                radius: 26
                                color: "transparent"
                                Image {
                                    anchors.fill: parent
                                    source: dash.p?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !(dash.p?.trackArtUrl)
                                text: "󰝚"
                                color: root.dim
                                font { family: root.font; pixelSize: 72 }
                            }
                        }
                        Column {
                            width: parent.width
                            spacing: 3
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                text: dash.p ? (dash.p.trackTitle || dash.p.identity) : "Aucune musique en cours"
                                color: root.fg
                                font { family: root.font; pixelSize: 15; bold: true }
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                text: dash.p?.trackArtist ?? ""
                                color: root.accent
                                font { family: root.font; pixelSize: 13 }
                            }
                        }
                        LiveBadge {
                            visible: root.isLive(dash.p)
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        // Progression
                        Rectangle {
                            visible: !!dash.p && (dash.p.length ?? 0) > 0 && !root.isLive(dash.p)
                            width: parent.width; height: 6; radius: 3
                            color: root.surface
                            Rectangle {
                                width: dash.p ? parent.width * Math.min(1, dash.p.position / Math.max(1, dash.p.length)) : 0
                                height: parent.height; radius: 3
                                color: root.accent
                            }
                            MouseArea {
                                anchors { fill: parent; topMargin: -8; bottomMargin: -8 }
                                enabled: dash.p?.canSeek ?? false
                                onClicked: m => dash.p.position = dash.p.length * m.x / width
                            }
                        }
                        Row {
                            visible: !!dash.p
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12
                            IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "󰒮"; enabledState: dash.p?.canGoPrevious ?? false; onClicked: dash.p.previous() }
                            IconButton { big: true; icon: dash.p?.isPlaying ? "󰏤" : "󰐊"; enabledState: dash.p?.canTogglePlaying ?? false; onClicked: dash.p.togglePlaying() }
                            IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "󰒭"; enabledState: dash.p?.canGoNext ?? false; onClicked: dash.p.next() }
                        }
                    }
                }
            }

            // ============ Onglet : Actualités ============
            // Grille « bento » unique (4 colonnes, tuiles 2×2 / 2×1 / 1×2 / 1×1 + tuiles texte), défilante,
            // filtres Tout / Nantes / France. Clic sur un article = l'ouvrir dans le navigateur.
            Item {
                id: newsTab
                visible: root.dashTab === "news"
                width: 1004
                height: 612
                property string filter: "all"          // all | local | national
                readonly property int cols: 4
                readonly property real gap: 10
                readonly property real colW: (width - gap * (cols - 1)) / cols
                readonly property real rowH: 150
                // Orientation politique des titres nationaux (cf. news-fetch : 10 articles par groupe)
                readonly property var leanColor: ({ gauche: "#ed8796", centre: "#eed49f", droite: "#8aadf4" })
                onFilterChanged: newsFlick.contentY = 0

                // Articles du filtre. Parité visible : le national alterne gauche / centre / droite (chaque groupe
                // du plus récent au plus ancien, en commençant par le groupe qui a l'article le plus frais), sinon le
                // titre qui publie le plus à cet instant prend la une et le haut de la grille. « Tout » alterne
                // national et Nantes.
                readonly property var list: {
                    const zip = qs => {
                        const out = []
                        for (let i = 0; qs.some(q => i < q.length); i++)
                            for (const q of qs) if (i < q.length) out.push(q[i])
                        return out
                    }
                    const byTs = (a, b) => b.ts - a.ts
                    const loc = (root.news?.local ?? []).map(a => Object.assign({ local: true }, a)).sort(byTs)
                    const all = (root.news?.national ?? []).map(a => Object.assign({ local: false }, a))
                    const groups = ["gauche", "centre", "droite"].map(g => all.filter(a => a.bucket === g).sort(byTs))
                                                                  .filter(q => q.length)
                    groups.sort((x, y) => y[0].ts - x[0].ts)
                    const nat = zip(groups)
                    return filter === "local" ? loc : filter === "national" ? nat : zip([nat, loc])
                }
                // Placement : motif de tailles répété, rangé au premier emplacement libre (sans trou au milieu)
                readonly property var layout: {
                    const pat = [[2, 2], [1, 1], [1, 1], [1, 2], [1, 1], [2, 1], [1, 1, "text"], [1, 1],
                                 [2, 1], [1, 2], [1, 1], [1, 1, "text"], [1, 1], [2, 2], [1, 1, "text"], [1, 1]]
                    const occ = [], out = []
                    const free = (r, c, w, h) => {
                        for (let y = r; y < r + h; y++)
                            for (let x = c; x < c + w; x++)
                                if (occ[y]?.[x]) return false
                        return true
                    }
                    list.forEach((a, i) => {
                        let [w, h, kind] = pat[i % pat.length]
                        if (!a.thumb) { w = 1; h = 1; kind = "text" }
                        for (let r = 0; ; r++) {
                            for (let c = 0; c <= cols - w; c++) {
                                if (!free(r, c, w, h)) continue
                                for (let y = r; y < r + h; y++) {
                                    occ[y] = occ[y] ?? []
                                    for (let x = c; x < c + w; x++) occ[y][x] = true
                                }
                                out.push({ a: a, x: c, y: r, w: w, h: h,
                                           kind: kind ?? (w === 2 && h === 2 ? "hero" : w === 2 ? "wide" : h === 2 ? "tall" : "small") })
                                return
                            }
                        }
                    })
                    return out
                }
                readonly property int rows: layout.reduce((m, t) => Math.max(m, t.y + t.h), 0)

                // En-tête : titre, filtres, fraîcheur
                Item {
                    id: newsHead
                    width: parent.width; height: 30
                    Text {
                        id: newsTitle
                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                        text: "󰎕  Actualités"
                        color: root.accent
                        font { family: root.font; pixelSize: 16; bold: true }
                    }
                    Row {
                        anchors { left: newsTitle.right; leftMargin: 18; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        Repeater {
                            model: [["all", "Tout"], ["local", "󰍎 Nantes"], ["national", "󰈙 France"]]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool sel: newsTab.filter === modelData[0]
                                width: nfT.implicitWidth + 20; height: 26; radius: 13
                                color: sel ? root.accent : nfMa.containsMouse ? root.surface : "transparent"
                                Text {
                                    id: nfT
                                    anchors.centerIn: parent
                                    text: parent.modelData[1]
                                    color: parent.sel ? root.bg : root.fg
                                    font { family: root.font; pixelSize: 11; bold: parent.sel }
                                }
                                MouseArea { id: nfMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: newsTab.filter = parent.modelData[0] }
                            }
                        }
                    }
                    // Équilibre des orientations (articles nationaux affichés) + fraîcheur
                    Row {
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        spacing: 12
                        Repeater {
                            model: newsTab.filter === "local" ? [] : ["gauche", "centre", "droite"]
                            delegate: Row {
                                required property string modelData
                                spacing: 5
                                Rectangle { width: 8; height: 8; radius: 4; color: newsTab.leanColor[parent.modelData]; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: parent.modelData.charAt(0).toUpperCase() + parent.modelData.slice(1) + " " + newsTab.list.filter(a => a.bucket === parent.modelData).length
                                    color: root.fg
                                    font { family: root.font; pixelSize: 11 }
                                }
                            }
                        }
                        Text {
                            text: (newsTab.filter === "local" ? newsTab.list.length + " articles  ·  " : "· ") + (root.news?.fetched ? "mis à jour il y a " + root.agoStr(root.news.fetched) : "")
                            color: root.dim
                            font { family: root.font; pixelSize: 11 }
                        }
                    }
                }

                DashCard {
                    visible: !newsTab.list.length
                    anchors { left: parent.left; right: parent.right; top: newsHead.bottom; bottom: parent.bottom; topMargin: 10 }
                    Column {
                        anchors.centerIn: parent
                        spacing: 14
                        Orb { look: "working"; size: 96; color: root.accent; visible: !root.news; anchors.horizontalCenter: parent.horizontalCenter }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.news ? "Aucune actualité" : "Chargement…"
                            color: root.dim
                            font { family: root.font; pixelSize: 12 }
                        }
                    }
                }

                Flickable {
                    id: newsFlick
                    anchors { left: parent.left; right: parent.right; top: newsHead.bottom; bottom: parent.bottom; topMargin: 10 }
                    clip: true
                    contentWidth: width
                    contentHeight: Math.max(0, newsTab.rows * (newsTab.rowH + newsTab.gap) - newsTab.gap)
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: 4000
                    maximumFlickVelocity: 6000

                    Repeater {
                        model: newsTab.layout
                        delegate: ClippingRectangle {
                            id: nTile
                            required property var modelData
                            readonly property var a: modelData.a
                            readonly property string kind: modelData.kind
                            readonly property bool img: kind !== "text"
                            x: modelData.x * (newsTab.colW + newsTab.gap)
                            y: modelData.y * (newsTab.rowH + newsTab.gap)
                            width: modelData.w * newsTab.colW + (modelData.w - 1) * newsTab.gap
                            height: modelData.h * newsTab.rowH + (modelData.h - 1) * newsTab.gap
                            radius: 20
                            color: img ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                                       : ntMa.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                                       : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Image {
                                visible: nTile.img
                                anchors.fill: parent
                                source: nTile.img && nTile.a.thumb ? "file://" + nTile.a.thumb : ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize { width: nTile.width * 1.2; height: nTile.height * 1.2 }
                                asynchronous: true
                                scale: ntMa.containsMouse ? 1.05 : 1
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            }
                            Rectangle {
                                visible: nTile.img
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop { position: nTile.kind === "tall" ? 0.3 : 0.15; color: "transparent" }
                                    GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.55) }
                                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.92) }
                                }
                            }
                            // Badge source (Nantes en couleur d'accent)
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; margins: nTile.kind === "hero" ? 14 : 10 }
                                width: srcRow.implicitWidth + 16; height: 20; radius: 10
                                color: nTile.a.local ? root.accent : nTile.img ? Qt.rgba(0, 0, 0, 0.6) : root.surface
                                Row {
                                    id: srcRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Rectangle {
                                        visible: !!nTile.a.bucket
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 7; height: 7; radius: 3.5
                                        color: newsTab.leanColor[nTile.a.bucket] ?? "transparent"
                                    }
                                    Text {
                                        text: (nTile.a.local ? "󰍎 " : "") + nTile.a.source
                                        color: nTile.a.local ? root.bg : nTile.img ? "#ffffff" : root.fg
                                        font { family: root.font; pixelSize: 10; bold: true }
                                    }
                                }
                            }
                            Column {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: nTile.kind === "hero" ? 18 : 12 }
                                spacing: nTile.kind === "hero" ? 6 : 4
                                Text {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: nTile.kind === "text" ? 3 : nTile.kind === "small" ? 3 : 3
                                    elide: Text.ElideRight
                                    text: nTile.a.title
                                    color: ntMa.containsMouse ? root.accent : nTile.img ? "#ffffff" : root.fg
                                    lineHeight: 1.1
                                    font {
                                        family: root.font; bold: true
                                        pixelSize: ({ hero: 20, wide: 15, tall: 14 })[nTile.kind] ?? 12
                                    }
                                }
                                Text {
                                    readonly property int lines: ({ hero: 3, wide: 1, tall: 5 })[nTile.kind] ?? 0
                                    visible: lines > 0 && !!nTile.a.desc
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: lines
                                    elide: Text.ElideRight
                                    text: nTile.a.desc ?? ""
                                    color: Qt.rgba(1, 1, 1, 0.78)
                                    font { family: root.font; pixelSize: nTile.kind === "hero" ? 12 : 11 }
                                }
                                Text {
                                    visible: !!nTile.a.ts
                                    text: "il y a " + root.agoStr(nTile.a.ts) + (nTile.a.lean ? "  ·  " + nTile.a.lean : "")
                                    color: nTile.img ? Qt.rgba(1, 1, 1, 0.6) : root.dim
                                    font { family: root.font; pixelSize: 10 }
                                }
                            }
                            MouseArea {
                                id: ntMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openUrl(nTile.a.link)
                            }
                        }
                    }
                }
                // Indicateur de défilement
                Rectangle {
                    visible: newsFlick.contentHeight > newsFlick.height
                    anchors.right: parent.right
                    anchors.rightMargin: -8
                    y: newsFlick.y + newsFlick.visibleArea.yPosition * newsFlick.height
                    width: 4; radius: 2
                    height: newsFlick.visibleArea.heightRatio * newsFlick.height
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, newsFlick.moving ? 0.5 : 0.2)
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                // Fondu en bas quand il reste du contenu
                Rectangle {
                    visible: newsFlick.contentY + newsFlick.height < newsFlick.contentHeight - 4
                    anchors { left: newsFlick.left; right: newsFlick.right; bottom: newsFlick.bottom }
                    height: 36
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.85) }
                    }
                }
            }

            // ============ Onglet : GitHub ============
            // Clic sur un élément = l'ouvrir dans le navigateur
            Column {
                id: ghTab
                visible: root.dashTab === "github"
                width: 1004
                spacing: 12
                readonly property var g: root.gh
                readonly property color green: root.wal ? root.wal.colors.color2 : "#a6da95"
                readonly property color red: root.wal ? root.wal.colors.color1 : "#ed8796"
                readonly property color yellow: root.wal ? root.wal.colors.color3 : "#eed49f"

                Row {
                    visible: !ghTab.g?.profile
                    spacing: 14
                    Orb { look: "reasoning"; size: 40; color: root.accent; visible: !ghTab.g?.error; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ghTab.g?.error ?? "Chargement de GitHub…"
                        color: root.dim
                        font { family: root.font; pixelSize: 14 }
                    }
                }

                Row {
                    visible: !!ghTab.g?.profile
                    spacing: 12

                    // Profil
                    DashCard {
                        id: ghProfile
                        readonly property var pr: ghTab.g?.profile ?? {}
                        width: 360; height: 220
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openUrl(ghProfile.pr.url) }
                        Rectangle {
                            id: ghAvatar
                            x: 20; y: 20
                            width: 76; height: 76; radius: 38
                            color: root.surface
                            ClippingRectangle {
                                anchors.fill: parent
                                radius: 38
                                color: "transparent"
                                Image {
                                    anchors.fill: parent
                                    source: ghProfile.pr.avatar ? "file://" + ghProfile.pr.avatar : ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize { width: 152; height: 152 }
                                    asynchronous: true
                                    cache: false
                                }
                            }
                        }
                        Column {
                            anchors { left: ghAvatar.right; leftMargin: 16; right: parent.right; rightMargin: 40; top: ghAvatar.top; topMargin: 4 }
                            spacing: 3
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: ghProfile.pr.name ?? ""
                                color: root.fg
                                font { family: root.font; pixelSize: 18; bold: true }
                            }
                            Text {
                                text: "@" + (ghProfile.pr.login ?? "") + (ghProfile.pr.plan ? "  ·  " + ghProfile.pr.plan : "")
                                color: root.accent
                                font { family: root.font; pixelSize: 12 }
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                visible: !!ghProfile.pr.status
                                text: "󰭹  " + ghProfile.pr.status
                                color: root.dim
                                font { family: root.font; pixelSize: 12; italic: true }
                            }
                        }
                        // Rafraîchir (ignore le cache)
                        Rectangle {
                            anchors { right: parent.right; top: parent.top; margins: 12 }
                            width: 28; height: 28; radius: 14
                            color: refMa.containsMouse ? root.surface : "transparent"
                            Text {
                                anchors.centerIn: parent
                                visible: !ghProc.running
                                text: "󰑐"
                                color: root.dim
                                font { family: root.font; pixelSize: 15 }
                            }
                            Orb { look: "working"; size: 22; color: root.accent; visible: ghProc.running; anchors.centerIn: parent }
                            MouseArea { id: refMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.ghRefresh() }
                        }
                        Column {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
                            spacing: 6
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: ghProfile.pr.bio ?? ""
                                color: root.fg
                                font { family: root.font; pixelSize: 12 }
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: [ghProfile.pr.company ? "󰏗 " + ghProfile.pr.company : "",
                                       ghProfile.pr.location ? "󰍎 " + ghProfile.pr.location : "",
                                       ghProfile.pr.since ? "󰃭 depuis " + new Date(ghProfile.pr.since * 1000).toLocaleDateString(Qt.locale("fr_FR"), "MMM yyyy") : ""]
                                      .filter(x => x).join("   ")
                                color: root.dim
                                font { family: root.font; pixelSize: 11 }
                            }
                            Row {
                                spacing: 6
                                Repeater {
                                    model: [[ghProfile.pr.followers, "abonnés"], [ghProfile.pr.following, "abonnements"],
                                            [ghProfile.pr.repos, "dépôts"], [ghProfile.pr.stars, "étoiles"]]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 75; height: 40; radius: 12
                                        color: root.surface
                                        Column {
                                            anchors.centerIn: parent
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: parent.parent.modelData[0] ?? "–"
                                                color: root.fg
                                                font { family: root.font; pixelSize: 13; bold: true }
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: parent.parent.modelData[1]
                                                color: root.dim
                                                font { family: root.font; pixelSize: 9 }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Contributions (calendrier façon GitHub, 1 an)
                    DashCard {
                        id: ghContrib
                        readonly property var c: ghTab.g?.contrib ?? {}
                        readonly property var days: c.days ?? []
                        // la grille commence un dimanche, comme sur GitHub
                        readonly property int pad: days.length ? new Date(days[0].date + "T12:00:00").getDay() : 0
                        property var hovered: null
                        width: 632; height: 220
                        Column {
                            anchors { left: parent.left; right: parent.right; margins: 18; verticalCenter: parent.verticalCenter }
                            spacing: 14
                            Item {
                                width: parent.width; height: 20
                                Text {
                                    text: "󰊤  " + (ghContrib.c.total ?? 0).toLocaleString(Qt.locale("fr_FR"), "f", 0) + " contributions cette année"
                                    color: root.accent
                                    font { family: root.font; pixelSize: 15; bold: true }
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: ghContrib.hovered
                                          ? ghContrib.hovered.count + " le " + new Date(ghContrib.hovered.date + "T12:00:00").toLocaleDateString(Qt.locale("fr_FR"), "d MMM yyyy")
                                          : "󰈸 série " + (ghContrib.c.streak ?? 0) + " j  ·  record " + (ghContrib.c.bestStreak ?? 0) + " j"
                                    color: root.dim
                                    font { family: root.font; pixelSize: 12 }
                                }
                            }
                            Grid {
                                anchors.horizontalCenter: parent.horizontalCenter
                                rows: 7
                                flow: Grid.TopToBottom
                                spacing: 2
                                Repeater {
                                    model: Array(ghContrib.pad).fill(null).concat(ghContrib.days)
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property int lvl: ["NONE", "FIRST_QUARTILE", "SECOND_QUARTILE", "THIRD_QUARTILE", "FOURTH_QUARTILE"].indexOf(modelData?.level ?? "")
                                        width: 9; height: 9; radius: 2
                                        color: !modelData ? "transparent"
                                             : lvl <= 0 ? root.surface
                                             : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, [0, 0.35, 0.55, 0.78, 1][lvl])
                                        border { width: ghContrib.hovered === modelData && modelData ? 1 : 0; color: root.fg }
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: !!parent.modelData
                                            onContainsMouseChanged: ghContrib.hovered = containsMouse ? parent.modelData : null
                                        }
                                    }
                                }
                            }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: [["󰜘", ghContrib.c.commits, "commits"], ["\uf407", ghContrib.c.prs, "PR"],
                                            ["\uf41b", ghContrib.c.issues, "issues"], ["󰈈", ghContrib.c.reviews, "reviews"],
                                            ["󰌾", ghContrib.c.private, "privées"]]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: cl.implicitWidth + 22; height: 28; radius: 14
                                        color: root.surface
                                        Text {
                                            id: cl
                                            anchors.centerIn: parent
                                            text: parent.modelData[0] + "  " + (parent.modelData[1] ?? 0) + " " + parent.modelData[2]
                                            color: root.fg
                                            font { family: root.font; pixelSize: 12 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    visible: !!ghTab.g?.profile
                    spacing: 12

                    // Facturation + notifications
                    DashCard {
                        id: ghBill
                        readonly property var b: ghTab.g?.billing ?? {}
                        readonly property var n: ghTab.g?.notifications
                        readonly property var items: (b.items ?? []).slice(0, 3)
                        readonly property real covered: (b.gross ?? 0) > 0 ? 1 - (b.net ?? 0) / b.gross : 1
                        width: 300; height: 400

                        Column {
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                            spacing: 12

                            Item {
                                width: parent.width; height: 22
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰄉  Facturation"
                                    color: root.accent
                                    font { family: root.font; pixelSize: 16; bold: true }
                                }
                                Rectangle {
                                    visible: !!ghTab.g?.profile?.plan
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    width: planT.implicitWidth + 16; height: 22; radius: 11
                                    color: root.surface
                                    Text {
                                        id: planT
                                        anchors.centerIn: parent
                                        text: "Plan " + (ghTab.g?.profile?.plan ?? "")
                                        color: root.fg
                                        font { family: root.font; pixelSize: 11 }
                                    }
                                }
                            }

                            // Sans le scope « user » : clic = l'autoriser dans un terminal
                            Rectangle {
                                visible: !!ghBill.b.error
                                width: parent.width; height: errT.implicitHeight + 24; radius: 16
                                color: errMa.containsMouse ? root.surface : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
                                Text {
                                    id: errT
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                                    wrapMode: Text.WordWrap
                                    text: (ghBill.b.error ?? "") + "\n\n󰌆  Cliquer pour autoriser l'accès"
                                    color: root.dim
                                    font { family: root.font; pixelSize: 11 }
                                }
                                MouseArea {
                                    id: errMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Quickshell.execDetached([root.home + "/.local/bin/term-run",
                                            "/home/linuxbrew/.linuxbrew/bin/gh auth refresh -h github.com -s user && ~/.local/bin/github-fetch --force >/dev/null && echo OK; read -p Entrée"])
                                        root.panel = ""
                                    }
                                }
                            }

                            // Montant du mois + part couverte par le forfait
                            Rectangle {
                                visible: !ghBill.b.error && ghBill.b.month !== undefined
                                width: parent.width; height: hero.implicitHeight + 28; radius: 16
                                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openUrl("https://github.com/settings/billing") }
                                Column {
                                    id: hero
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                                    spacing: 6
                                    Text {
                                        text: ghBill.b.month ? new Date(ghBill.b.month + "-15T12:00:00").toLocaleDateString(Qt.locale("fr_FR"), "MMMM yyyy") : ""
                                        color: root.dim
                                        font { family: root.font; pixelSize: 12; capitalization: Font.Capitalize }
                                    }
                                    Row {
                                        spacing: 8
                                        Text {
                                            text: root.money(ghBill.b.net)
                                            color: root.fg
                                            font { family: root.font; pixelSize: 30; bold: true }
                                        }
                                        Text {
                                            anchors.baseline: parent.children[0].baseline
                                            text: "à payer"
                                            color: root.dim
                                            font { family: root.font; pixelSize: 12 }
                                        }
                                    }
                                    Rectangle {
                                        width: parent.width; height: 6; radius: 3
                                        color: root.surface
                                        Rectangle {
                                            width: parent.width * Math.max(0, Math.min(1, ghBill.covered)); height: parent.height; radius: 3
                                            color: root.accent
                                        }
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: root.money(ghBill.b.gross) + " d'usage  ·  " + Math.round(ghBill.covered * 100) + " % inclus"
                                        color: root.dim
                                        font { family: root.font; pixelSize: 11 }
                                    }
                                }
                            }

                            // Détail par produit
                            Column {
                                visible: !ghBill.b.error && ghBill.b.month !== undefined
                                width: parent.width
                                spacing: 4
                                Repeater {
                                    model: ghBill.items
                                    delegate: Item {
                                        required property var modelData
                                        width: parent.width; height: 34
                                        Column {
                                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                                            Text {
                                                text: (parent.parent.modelData.product.charAt(0).toUpperCase() + parent.parent.modelData.product.slice(1)).replace(/_/g, " ")
                                                color: root.fg
                                                font { family: root.font; pixelSize: 12; bold: true }
                                            }
                                            Text {
                                                text: Math.round(parent.parent.modelData.quantity).toLocaleString(Qt.locale("fr_FR"), "f", 0) + " " + parent.parent.modelData.unit.toLowerCase()
                                                color: root.dim
                                                font { family: root.font; pixelSize: 11 }
                                            }
                                        }
                                        Text {
                                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                            text: root.money(parent.modelData.gross)
                                            color: root.fg
                                            font { family: root.font; pixelSize: 12 }
                                        }
                                    }
                                }
                                Text {
                                    visible: (ghBill.b.premium?.quantity ?? 0) > 0
                                    leftPadding: 4
                                    text: "Copilot premium  ·  " + Math.round(ghBill.b.premium?.quantity ?? 0) + " requêtes"
                                    color: root.dim
                                    font { family: root.font; pixelSize: 11 }
                                }
                            }
                        }

                        // Notifications, calées en bas de la carte
                        Column {
                            visible: !!ghBill.n
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18 }
                            spacing: 6
                            Rectangle {
                                width: parent.width; height: 34; radius: 12
                                color: notMa.containsMouse ? root.surface : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
                                Text {
                                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: "󰂚  " + (ghBill.n?.unread ?? 0) + (ghBill.n?.more ? "+" : "") + " notifications non lues"
                                    color: root.fg
                                    font { family: root.font; pixelSize: 12; bold: true }
                                }
                                Text {
                                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: "󰁔"
                                    color: root.dim
                                    font { family: root.font; pixelSize: 12 }
                                }
                                MouseArea { id: notMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openUrl("https://github.com/notifications") }
                            }
                            Repeater {
                                model: (ghBill.n?.items ?? []).slice(0, ghBill.b.error || ghBill.items.length > 1 ? 2 : 3)
                                delegate: Item {
                                    required property var modelData
                                    width: parent.width; height: 32
                                    Text {
                                        id: nIcon
                                        anchors { left: parent.left; leftMargin: 6; top: parent.top; topMargin: 1 }
                                        text: parent.modelData.type === "PullRequest" ? "" : ""
                                        color: root.accent
                                        font { family: root.font; pixelSize: 12 }
                                    }
                                    Column {
                                        anchors { left: nIcon.right; leftMargin: 8; right: parent.right; rightMargin: 4 }
                                        Text {
                                            width: parent.width; elide: Text.ElideRight
                                            text: parent.parent.modelData.title
                                            color: root.fg
                                            font { family: root.font; pixelSize: 11 }
                                        }
                                        Text {
                                            width: parent.width; elide: Text.ElideRight
                                            text: parent.parent.modelData.repo + "  ·  il y a " + root.agoStr(parent.parent.modelData.ts)
                                            color: root.dim
                                            font { family: root.font; pixelSize: 10 }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Activité récente
                    DashCard {
                        width: 310; height: 400
                        Text {
                            id: evTitle
                            anchors { left: parent.left; top: parent.top; margins: 18 }
                            text: "󰄨  Activité récente"
                            color: root.accent
                            font { family: root.font; pixelSize: 16; bold: true }
                        }
                        ListView {
                            anchors { left: parent.left; right: parent.right; top: evTitle.bottom; bottom: parent.bottom; margins: 12; topMargin: 10 }
                            clip: true
                            spacing: 2
                            model: ghTab.g?.events ?? []
                            delegate: Rectangle {
                                id: ev
                                required property var modelData
                                width: ListView.view.width
                                height: evCol.implicitHeight + 12
                                radius: 10
                                color: evMa.containsMouse ? root.surface : "transparent"
                                Text {
                                    id: evIcon
                                    anchors { left: parent.left; leftMargin: 8; top: parent.top; topMargin: 7 }
                                    width: 18
                                    text: ev.modelData.icon
                                    color: root.accent
                                    font { family: root.font; pixelSize: 14 }
                                }
                                Column {
                                    id: evCol
                                    anchors { left: evIcon.right; leftMargin: 8; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    spacing: 1
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                                        text: ev.modelData.text
                                        color: evMa.containsMouse ? root.accent : root.fg
                                        font { family: root.font; pixelSize: 12 }
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: ev.modelData.repo + "  ·  il y a " + root.agoStr(ev.modelData.ts)
                                        color: root.dim
                                        font { family: root.font; pixelSize: 10 }
                                    }
                                }
                                MouseArea { id: evMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openUrl(ev.modelData.url) }
                            }
                        }
                    }

                    // PR & issues
                    DashCard {
                        id: ghLists
                        readonly property var lists: ghTab.g?.lists ?? {}
                        readonly property var cur: lists[root.ghList] ?? { count: 0, items: [] }
                        width: 370; height: 400
                        Row {
                            id: ghChips
                            anchors { left: parent.left; top: parent.top; margins: 14 }
                            spacing: 2
                            Repeater {
                                model: [["prs", "PR"], ["reviews", "Revues"], ["assigned", "Assignées"], ["issues", "Issues"], ["ci", "CI"]]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root.ghList === modelData[0]
                                    width: chT.implicitWidth + 12; height: 28; radius: 14
                                    color: sel ? root.accent : chMa.containsMouse ? root.surface : "transparent"
                                    Text {
                                        id: chT
                                        anchors.centerIn: parent
                                        text: parent.modelData[1] + " " + (ghLists.lists[parent.modelData[0]]?.count ?? 0)
                                        color: parent.sel ? root.bg : root.fg
                                        font { family: root.font; pixelSize: 11; bold: parent.sel }
                                    }
                                    MouseArea { id: chMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.ghList = parent.modelData[0] }
                                }
                            }
                        }
                        Text {
                            anchors { top: ghChips.bottom; topMargin: 30; horizontalCenter: parent.horizontalCenter }
                            visible: !ghLists.cur.items.length
                            text: "Rien en attente 󰄬"
                            color: root.dim
                            font { family: root.font; pixelSize: 12 }
                        }
                        ListView {
                            anchors { left: parent.left; right: parent.right; top: ghChips.bottom; bottom: allLink.top; margins: 12; topMargin: 10; bottomMargin: 4 }
                            clip: true
                            spacing: 2
                            model: ghLists.cur.items
                            delegate: Rectangle {
                                id: it
                                required property var modelData
                                readonly property bool isPr: modelData.draft !== undefined
                                readonly property bool isRun: modelData.workflow !== undefined
                                // échec en quelques secondes sans démarrer = run bloqué (facturation, quota…)
                                readonly property bool notStarted: isRun && modelData.conclusion === "failure" && modelData.duration <= 5
                                width: ListView.view.width
                                height: itCol.implicitHeight + 12
                                radius: 10
                                color: itMa.containsMouse ? root.surface : "transparent"
                                Text {
                                    id: itIcon
                                    anchors { left: parent.left; leftMargin: 8; top: parent.top; topMargin: 7 }
                                    width: 18
                                    // PR : état des checks / brouillon ; issue : ouverte
                                    text: it.isRun ? (it.modelData.status !== "completed" ? "󰔟" : it.modelData.conclusion === "success" ? "󰄬"
                                                      : it.modelData.conclusion === "failure" ? "󰅖" : "󰜺")
                                        : it.isPr ? (it.modelData.draft ? "\uf4dd" : "\uf407") : "\uf41b"
                                    color: it.isRun ? (it.modelData.status !== "completed" ? ghTab.yellow : it.modelData.conclusion === "success" ? ghTab.green
                                                       : it.modelData.conclusion === "failure" ? ghTab.red : root.dim)
                                         : !it.isPr ? ghTab.green
                                         : it.modelData.draft ? root.dim
                                         : it.modelData.checks === "FAILURE" || it.modelData.checks === "ERROR" ? ghTab.red
                                         : it.modelData.checks === "PENDING" || it.modelData.checks === "EXPECTED" ? ghTab.yellow
                                         : it.modelData.checks === "SUCCESS" ? ghTab.green
                                         : root.accent
                                    font { family: root.font; pixelSize: 14 }
                                }
                                Column {
                                    id: itCol
                                    anchors { left: itIcon.right; leftMargin: 8; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    spacing: 1
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                                        text: it.isRun ? it.modelData.workflow + " : " + it.modelData.title : it.modelData.title
                                        color: itMa.containsMouse ? root.accent : root.fg
                                        font { family: root.font; pixelSize: 12 }
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: it.isRun
                                              ? it.modelData.repo.split("/")[1] + " · " + it.modelData.branch + "  ·  "
                                                + (it.notStarted ? "non démarré" : it.modelData.status !== "completed" ? "en cours"
                                                   : Math.floor(it.modelData.duration / 60) + " min " + it.modelData.duration % 60 + " s")
                                                + "  ·  il y a " + root.agoStr(it.modelData.ts)
                                              : it.modelData.repo.split("/")[1] + "#" + it.modelData.number + "  ·  il y a " + root.agoStr(it.modelData.ts)
                                              + (it.modelData.review === "APPROVED" ? "  ·  󰄬 approuvée"
                                                 : it.modelData.review === "CHANGES_REQUESTED" ? "  ·  changements demandés" : "")
                                              + (it.modelData.comments ? "  ·  󰅺 " + it.modelData.comments : "")
                                        color: it.notStarted ? ghTab.red : root.dim
                                        font { family: root.font; pixelSize: 10 }
                                    }
                                }
                                MouseArea { id: itMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openUrl(it.modelData.url) }
                            }
                        }
                        Text {
                            id: allLink
                            anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
                            text: "Tout voir sur GitHub 󰁔"
                            color: allMa.containsMouse ? root.accent : root.dim
                            font { family: root.font; pixelSize: 11 }
                            MouseArea {
                                id: allMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openUrl(root.ghList === "ci"
                                    ? "https://github.com/" + (ghLists.cur.items[0]?.repo ?? "") + "/actions"
                                    : "https://github.com/" + {
                                        prs: "pulls", reviews: "pulls/review-requested", assigned: "issues/assigned", issues: "issues"
                                    }[root.ghList])
                            }
                        }
                    }
                }
            }

            // ============ Onglet : Cyber ============
            // Clic sur un élément = l'ouvrir dans le navigateur
            Column {
                id: cyTab
                visible: root.dashTab === "cyber"
                width: 1004
                spacing: 12
                readonly property var c: root.cyber
                readonly property color red: root.wal ? root.wal.colors.color1 : "#ed8796"

                Row {
                    visible: !cyTab.c
                    spacing: 14
                    Orb { look: "searching"; size: 40; color: root.accent; visible: true; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Chargement de la veille (NVD peut prendre ~10 s)…"
                        color: root.dim
                        font { family: root.font; pixelSize: 14 }
                    }
                }

                // Chiffres clés
                Row {
                    visible: !!cyTab.c
                    spacing: 12
                    Repeater {
                        model: [["󰀦", cyTab.c?.stats?.critical, "CVE critiques", "CVSS ≥ 9 · 72 h", "cves", root.cvssColor(9)],
                                ["󰒃", cyTab.c?.stats?.high, "CVE élevées", "CVSS 7 – 8,9 · 72 h", "cves", root.cvssColor(7)],
                                ["󰈸", cyTab.c?.stats?.kevWeek, "Exploitées", "ajouts CISA KEV · 7 j", "kev", cyTab.red],
                                ["󰀨", cyTab.c?.stats?.alerts, "Alertes CERT-FR", "30 derniers jours", "certfr", root.accent]]
                        delegate: DashCard {
                            required property var modelData
                            width: 242; height: 84
                            Rectangle {
                                id: stIcon
                                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                                width: 48; height: 48; radius: 16
                                color: Qt.rgba(Qt.color(parent.modelData[5]).r, Qt.color(parent.modelData[5]).g, Qt.color(parent.modelData[5]).b, 0.16)
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.parent.modelData[0]
                                    color: parent.parent.modelData[5]
                                    font { family: root.font; pixelSize: 22 }
                                }
                            }
                            Column {
                                anchors { left: stIcon.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                Text {
                                    text: (parent.parent.modelData[1] ?? "–") + "  " + parent.parent.modelData[2]
                                    color: root.fg
                                    font { family: root.font; pixelSize: 15; bold: true }
                                }
                                Text {
                                    text: parent.parent.modelData[3]
                                    color: root.dim
                                    font { family: root.font; pixelSize: 11 }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const t = parent.modelData[4]
                                    if (t === "certfr") root.cyberNews = "certfr"; else root.cyberCve = t
                                }
                            }
                        }
                    }
                }

                Row {
                    visible: !!cyTab.c
                    spacing: 12

                    // Actualités / CERT-FR
                    DashCard {
                        id: cyNews
                        width: 496; height: 500
                        Row {
                            id: cyNewsChips
                            anchors { left: parent.left; top: parent.top; margins: 14 }
                            spacing: 4
                            Repeater {
                                model: [["news", "󰎕  Actualités"], ["certfr", "󰀨  CERT-FR"]]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root.cyberNews === modelData[0]
                                    width: cnT.implicitWidth + 20; height: 28; radius: 14
                                    color: sel ? root.accent : cnMa.containsMouse ? root.surface : "transparent"
                                    Text {
                                        id: cnT
                                        anchors.centerIn: parent
                                        text: parent.modelData[1]
                                        color: parent.sel ? root.bg : root.fg
                                        font { family: root.font; pixelSize: 12; bold: parent.sel }
                                    }
                                    MouseArea { id: cnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.cyberNews = parent.modelData[0] }
                                }
                            }
                        }
                        ListView {
                            anchors { left: parent.left; right: parent.right; top: cyNewsChips.bottom; bottom: parent.bottom; margins: 12; topMargin: 10 }
                            clip: true
                            spacing: 2
                            model: root.cyberNews === "certfr" ? (cyTab.c?.certfr ?? []) : (cyTab.c?.news ?? [])
                            delegate: Rectangle {
                                id: cn
                                required property var modelData
                                readonly property string tag: modelData.kind ? modelData.kind.toUpperCase() : modelData.source
                                readonly property color tagColor: modelData.kind === "alerte" ? cyTab.red
                                                                : modelData.kind === "avis" ? root.cvssColor(7) : root.accent
                                width: ListView.view.width
                                height: cnCol.implicitHeight + 14
                                radius: 10
                                color: cnItemMa.containsMouse ? root.surface : "transparent"
                                Column {
                                    id: cnCol
                                    anchors { left: parent.left; right: parent.right; margins: 10; verticalCenter: parent.verticalCenter }
                                    spacing: 3
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                                        text: cn.modelData.title
                                        color: cnItemMa.containsMouse ? root.accent : root.fg
                                        font { family: root.font; pixelSize: 13 }
                                    }
                                    Row {
                                        spacing: 8
                                        Rectangle {
                                            width: tagT.implicitWidth + 12; height: 16; radius: 8
                                            color: Qt.rgba(cn.tagColor.r, cn.tagColor.g, cn.tagColor.b, 0.18)
                                            Text {
                                                id: tagT
                                                anchors.centerIn: parent
                                                text: cn.tag
                                                color: cn.tagColor
                                                font { family: root.font; pixelSize: 10; bold: true }
                                            }
                                        }
                                        Text {
                                            text: cn.modelData.ts ? "il y a " + root.agoStr(cn.modelData.ts) : ""
                                            color: root.dim
                                            font { family: root.font; pixelSize: 11 }
                                        }
                                    }
                                }
                                MouseArea { id: cnItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openUrl(cn.modelData.link) }
                            }
                        }
                    }

                    // CVE
                    DashCard {
                        id: cyCve
                        readonly property var list: root.cyberCve === "kev" ? (cyTab.c?.kev ?? [])
                                                  : root.cyberCve === "watch" ? (cyTab.c?.cves ?? []).concat(cyTab.c?.kev ?? []).filter(x => x.watch)
                                                  : (cyTab.c?.cves ?? [])
                        width: 496; height: 500
                        Row {
                            id: cyCveChips
                            anchors { left: parent.left; top: parent.top; margins: 14 }
                            spacing: 4
                            Repeater {
                                model: [["cves", "󰀦  CVSS ≥ 7"], ["kev", "󰈸  Exploitées"], ["watch", "󰒃  Me concernent"]]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root.cyberCve === modelData[0]
                                    width: ccT.implicitWidth + 20; height: 28; radius: 14
                                    color: sel ? root.accent : ccMa.containsMouse ? root.surface : "transparent"
                                    Text {
                                        id: ccT
                                        anchors.centerIn: parent
                                        text: parent.modelData[1]
                                        color: parent.sel ? root.bg : root.fg
                                        font { family: root.font; pixelSize: 12; bold: parent.sel }
                                    }
                                    MouseArea { id: ccMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.cyberCve = parent.modelData[0] }
                                }
                            }
                        }
                        Text {
                            anchors { top: cyCveChips.bottom; topMargin: 30; horizontalCenter: parent.horizontalCenter }
                            visible: !cyCve.list.length
                            text: root.cyberCve === "watch" ? "Rien qui touche tes logiciels 󰄬" : "Aucune CVE"
                            color: root.dim
                            font { family: root.font; pixelSize: 12 }
                        }
                        ListView {
                            anchors { left: parent.left; right: parent.right; top: cyCveChips.bottom; bottom: parent.bottom; margins: 12; topMargin: 10 }
                            clip: true
                            spacing: 2
                            model: cyCve.list
                            delegate: Rectangle {
                                id: cv
                                required property var modelData
                                readonly property color sc: cv.modelData.score ? root.cvssColor(cv.modelData.score) : cyTab.red
                                width: ListView.view.width
                                height: Math.max(cvCol.implicitHeight, 46) + 14
                                radius: 10
                                color: cvMa.containsMouse ? root.surface : "transparent"
                                // Score CVSS (ou KEV si la CVE n'est pas dans la fenêtre NVD)
                                Rectangle {
                                    id: cvBadge
                                    anchors { left: parent.left; leftMargin: 8; top: parent.top; topMargin: 7 }
                                    width: 46; height: 46; radius: 14
                                    color: Qt.rgba(cv.sc.r, cv.sc.g, cv.sc.b, 0.18)
                                    Column {
                                        anchors.centerIn: parent
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: cv.modelData.score ? cv.modelData.score.toFixed(1).replace(".", ",") : "KEV"
                                            color: cv.sc
                                            font { family: root.font; pixelSize: cv.modelData.score ? 15 : 12; bold: true }
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            visible: !!cv.modelData.version
                                            text: "v" + cv.modelData.version
                                            color: root.dim
                                            font { family: root.font; pixelSize: 9 }
                                        }
                                    }
                                }
                                Column {
                                    id: cvCol
                                    anchors { left: cvBadge.right; leftMargin: 12; right: parent.right; rightMargin: 10; top: parent.top; topMargin: 7 }
                                    spacing: 3
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: cv.modelData.id + (cv.modelData.product ? "  ·  " + cv.modelData.product : "")
                                        color: cvMa.containsMouse ? root.accent : root.fg
                                        font { family: root.font; pixelSize: 12; bold: true }
                                    }
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                                        text: cv.modelData.desc
                                        color: root.fg
                                        font { family: root.font; pixelSize: 11 }
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: [cv.modelData.kev ? "󰈸 exploitée" : "",
                                               cv.modelData.ransomware ? "󰯄 ransomware" : "",
                                               cv.modelData.watch ? "󰒃 te concerne" : "",
                                               cv.modelData.epss != null ? "EPSS " + (cv.modelData.epss * 100).toFixed(cv.modelData.epss < 0.1 ? 1 : 0).replace(".", ",") + " %" : "",
                                               (cv.modelData.kev && root.cyberCve === "kev" ? "ajoutée il y a " : "il y a ") + root.agoStr(cv.modelData.ts)]
                                              .filter(x => x).join("  ·  ")
                                        color: cv.modelData.kev || cv.modelData.watch ? cv.sc : root.dim
                                        font { family: root.font; pixelSize: 10 }
                                    }
                                }
                                MouseArea { id: cvMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openUrl(cv.modelData.link) }
                            }
                        }
                    }
                }
            }

            // ============ Onglet : Agenda ============
            Row {
                id: agTab
                visible: root.dashTab === "agenda"
                spacing: 12
                readonly property var a: root.agenda
                readonly property bool hasToday: root.agendaDays.length > 0 && root.dayLabel(root.agendaDays[0].day).startsWith("Aujourd'hui")
                readonly property var today: hasToday ? root.agendaDays[0].events : []
                readonly property var later: hasToday ? root.agendaDays.slice(1) : root.agendaDays

                Column {
                    spacing: 12

                    // Aujourd'hui
                    DashCard {
                        width: 330; height: 196
                        Column {
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                            spacing: 4
                            Text {
                                text: { const s = dash.now.toLocaleDateString(Qt.locale("fr_FR"), "dddd d MMMM"); return s.charAt(0).toUpperCase() + s.slice(1) }
                                color: root.accent
                                font { family: root.font; pixelSize: 18; bold: true }
                            }
                            Text {
                                text: agTab.today.length ? agTab.today.length + " événement" + (agTab.today.length > 1 ? "s" : "") + " aujourd'hui"
                                                         : "Rien de prévu aujourd'hui"
                                color: root.dim
                                font { family: root.font; pixelSize: 12 }
                                bottomPadding: 8
                            }
                            Repeater {
                                model: agTab.today.slice(0, 2)
                                delegate: Rectangle {
                                    id: tev
                                    required property var modelData
                                    readonly property bool now: !modelData.allDay && modelData.start * 1000 <= dash.now.getTime() && modelData.end * 1000 > dash.now.getTime()
                                    width: parent.width; height: 48; radius: 14
                                    color: tev.now ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
                                    Rectangle {
                                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                        width: 4; height: 30; radius: 2
                                        color: root.agendaColor(tev.modelData)
                                    }
                                    Column {
                                        anchors { left: parent.left; leftMargin: 24; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                        spacing: 2
                                        Text {
                                            width: parent.width; elide: Text.ElideRight
                                            text: tev.modelData.title
                                            color: root.fg
                                            font { family: root.font; pixelSize: 13; bold: true }
                                        }
                                        Text {
                                            width: parent.width; elide: Text.ElideRight
                                            text: (tev.modelData.allDay ? "Toute la journée" : root.hm(tev.modelData.start) + " – " + root.hm(tev.modelData.end))
                                                  + (tev.now ? "  ·  en cours" : "") + (tev.modelData.location ? "  ·  󰍎 " + tev.modelData.location : "")
                                            color: root.dim
                                            font { family: root.font; pixelSize: 11 }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !!tev.modelData.link
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openUrl(tev.modelData.link)
                                    }
                                }
                            }
                        }
                    }

                    // Prochains jours (agendas perso)
                    DashCard {
                        width: 330; height: 376
                        Text {
                            id: agTitle
                            anchors { left: parent.left; top: parent.top; margins: 20 }
                            text: "󰃭  À venir"
                            color: root.accent
                            font { family: root.font; pixelSize: 16; bold: true }
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: 20; verticalCenter: agTitle.verticalCenter }
                            spacing: 10
                            Repeater {
                                model: agTab.a?.calendars ?? []
                                delegate: Row {
                                    required property var modelData
                                    spacing: 5
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: root.agendaColor({ calendar: parent.modelData.name, color: parent.modelData.color }) }
                                    Text { text: parent.modelData.name; color: root.dim; font { family: root.font; pixelSize: 10 } }
                                }
                            }
                        }
                        Text {
                            id: agErr
                            anchors { left: parent.left; right: parent.right; top: agTitle.bottom; margins: 20; topMargin: 6 }
                            visible: (agTab.a?.errors ?? []).length > 0 || agTab.a?.error === "noconfig"
                            wrapMode: Text.WordWrap
                            text: agTab.a?.error === "noconfig" ? "Ajoute l'adresse iCal secrète de ton Google Agenda dans ~/.config/quickshell/agenda.json"
                                                                : "󰀦 " + (agTab.a?.errors ?? []).join("\n")
                            color: root.cvssColor(7)
                            font { family: root.font; pixelSize: 10 }
                        }
                        Flickable {
                            id: agFlick
                            anchors { left: parent.left; right: parent.right; top: agErr.visible ? agErr.bottom : agTitle.bottom; bottom: parent.bottom; margins: 14; topMargin: 12 }
                            clip: true
                            contentHeight: agDays.implicitHeight
                            Column {
                                id: agDays
                                width: agFlick.width
                                spacing: 12
                                Row {
                                    visible: !agTab.later.length
                                    spacing: 10
                                    Orb { look: "working"; size: 28; color: root.accent; visible: !agTab.a; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: agTab.a ? "Rien d'autre dans les 14 jours" : "Chargement…"
                                        color: root.dim
                                        font { family: root.font; pixelSize: 12 }
                                    }
                                }
                                Repeater {
                                    model: agTab.later
                                    delegate: Column {
                                        id: agDay
                                        required property var modelData
                                        width: agDays.width
                                        spacing: 4
                                        Text {
                                            text: root.dayLabel(agDay.modelData.day)
                                            color: root.fg
                                            font { family: root.font; pixelSize: 12; bold: true }
                                        }
                                        Repeater {
                                            model: agDay.modelData.events
                                            delegate: Rectangle {
                                                id: aev
                                                required property var modelData
                                                width: agDay.width; height: 40; radius: 12
                                                color: aevMa.containsMouse ? root.surface : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
                                                Rectangle {
                                                    id: aevBar
                                                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                                    width: 4; height: 24; radius: 2
                                                    color: root.agendaColor(aev.modelData)
                                                }
                                                Column {
                                                    anchors { left: aevBar.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                                    Text {
                                                        width: parent.width; elide: Text.ElideRight
                                                        text: aev.modelData.title
                                                        color: root.fg
                                                        font { family: root.font; pixelSize: 12 }
                                                    }
                                                    Text {
                                                        width: parent.width; elide: Text.ElideRight
                                                        text: (aev.modelData.allDay ? "Journée" : root.hm(aev.modelData.start) + " – " + root.hm(aev.modelData.end))
                                                              + (aev.modelData.link ? "  ·  󰕧 visio" : aev.modelData.location ? "  ·  " + aev.modelData.location : "")
                                                        color: root.dim
                                                        font { family: root.font; pixelSize: 10 }
                                                    }
                                                }
                                                MouseArea {
                                                    id: aevMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: !!aev.modelData.link
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.openUrl(aev.modelData.link)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Sortir à Nantes (agenda open data de Nantes Métropole)
                DashCard {
                    id: nt
                    readonly property var list: root.eventsFiltered
                    width: 662; height: 584
                    Text {
                        id: ntTitle
                        anchors { left: parent.left; top: parent.top; margins: 20 }
                        text: "󰍎  Sortir à Nantes"
                        color: root.accent
                        font { family: root.font; pixelSize: 16; bold: true }
                    }
                    // Barre de recherche
                    Rectangle {
                        anchors { left: ntTitle.right; leftMargin: 16; right: ntCount.left; rightMargin: 12; verticalCenter: ntTitle.verticalCenter }
                        height: 28; radius: 14
                        color: root.bg
                        border { width: 1; color: ntSearch.activeFocus ? root.accent : root.surface }
                        Text {
                            id: ntSearchIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: "󰍉"; color: ntSearch.activeFocus ? root.accent : root.dim
                            font { family: root.font; pixelSize: 13 }
                        }
                        TextInput {
                            id: ntSearch
                            anchors { left: ntSearchIcon.right; leftMargin: 6; right: ntClear.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            clip: true
                            color: root.fg; selectionColor: root.accent
                            font { family: root.font; pixelSize: 12 }
                            text: root.evQuery
                            onTextEdited: root.evQuery = text
                            Keys.onEscapePressed: event => { if (text) { root.evQuery = ""; text = "" } else { focus = false; event.accepted = false } }
                            Text { visible: !parent.text && !parent.activeFocus; text: "Rechercher (convention, manga, salle…)"; color: root.dim; font: parent.font; width: parent.width; elide: Text.ElideRight }
                        }
                        MouseArea { anchors.fill: parent; z: -1; cursorShape: Qt.IBeamCursor; onClicked: ntSearch.forceActiveFocus() }
                        Text {
                            id: ntClear
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            visible: !!root.evQuery
                            width: visible ? implicitWidth : 0
                            text: "󰅖"; color: ntClearMa.containsMouse ? root.accent : root.dim
                            font { family: root.font; pixelSize: 12 }
                            MouseArea { id: ntClearMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.evQuery = ""; ntSearch.text = "" } }
                        }
                    }
                    Text {
                        id: ntCount
                        anchors { right: parent.right; rightMargin: 20; verticalCenter: ntTitle.verticalCenter }
                        text: nt.list.length + " événement" + (nt.list.length > 1 ? "s" : "") + (root.events?.origin ? "  ·  󰋜 " + root.events.origin.replace(/ \d{5} .*$/, "") : "")
                        color: root.dim
                        font { family: root.font; pixelSize: 11 }
                    }
                    // Filtres : quand, quoi, prix
                    Column {
                        id: ntFilters
                        anchors { left: parent.left; right: parent.right; top: ntTitle.bottom; margins: 16; topMargin: 12 }
                        spacing: 6
                        Row {
                            spacing: 4
                            Repeater {
                                model: [["today", "Aujourd'hui"], ["tomorrow", "Demain"], ["weekend", "Ce week-end"], ["week", "7 jours"], ["later", "3 mois"]]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root.evWhen === modelData[0]
                                    width: fwT.implicitWidth + 20; height: 26; radius: 13
                                    color: sel ? root.accent : fwMa.containsMouse ? root.surface : "transparent"
                                    Text {
                                        id: fwT
                                        anchors.centerIn: parent
                                        text: parent.modelData[1]
                                        color: parent.sel ? root.bg : root.fg
                                        font { family: root.font; pixelSize: 11; bold: parent.sel }
                                    }
                                    MouseArea { id: fwMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.evWhen = parent.modelData[0] }
                                }
                            }
                            Item { width: 12; height: 1 }
                            Rectangle {
                                width: frT.implicitWidth + 20; height: 26; radius: 13
                                color: root.evFree ? root.accent : frMa.containsMouse ? root.surface : "transparent"
                                border { width: root.evFree ? 0 : 1; color: root.surface }
                                Text {
                                    id: frT
                                    anchors.centerIn: parent
                                    text: "󰄬 Gratuit"
                                    color: root.evFree ? root.bg : root.fg
                                    font { family: root.font; pixelSize: 11; bold: root.evFree }
                                }
                                MouseArea { id: frMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.evFree = !root.evFree }
                            }
                        }
                        Flow {
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: root.evCategories
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root.evCat === modelData[0]
                                    width: fcT.implicitWidth + 12; height: 24; radius: 12
                                    color: sel ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25) : fcMa.containsMouse ? root.surface : "transparent"
                                    Text {
                                        id: fcT
                                        anchors.centerIn: parent
                                        text: parent.modelData[1]
                                        color: parent.sel ? root.accent : root.dim
                                        font { family: root.font; pixelSize: 11; bold: parent.sel }
                                    }
                                    MouseArea { id: fcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.evCat = parent.modelData[0] }
                                }
                            }
                        }
                    }
                    Column {
                        anchors { top: ntFilters.bottom; topMargin: 40; horizontalCenter: parent.horizontalCenter }
                        visible: !nt.list.length
                        spacing: 14
                        Orb { look: "searching"; size: 72; color: root.accent; visible: !root.events; anchors.horizontalCenter: parent.horizontalCenter }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.events ? (root.events.error ? "󰀦 " + root.events.error : "Rien avec ces filtres") : "Chargement des événements…"
                            color: root.dim
                            font { family: root.font; pixelSize: 12 }
                        }
                    }
                    ListView {
                        anchors { left: parent.left; right: parent.right; top: ntFilters.bottom; bottom: parent.bottom; margins: 12; topMargin: 10 }
                        clip: true
                        spacing: 4
                        model: nt.list
                        delegate: Rectangle {
                            id: ne
                            required property var modelData
                            width: ListView.view.width; height: 76; radius: 12
                            color: neMa.containsMouse ? root.surface : "transparent"
                            ClippingRectangle {
                                id: neImg
                                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                width: 100; height: 64; radius: 10
                                color: root.surface
                                Image {
                                    anchors.fill: parent
                                    source: ne.modelData.thumb ? "file://" + ne.modelData.thumb : ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize { width: 200; height: 128 }
                                    asynchronous: true
                                    scale: neMa.containsMouse ? 1.08 : 1
                                    Behavior on scale { NumberAnimation { duration: 150 } }
                                }
                            }
                            Column {
                                anchors { left: neImg.right; leftMargin: 14; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                spacing: 3
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: ne.modelData.title
                                    color: neMa.containsMouse ? root.accent : root.fg
                                    font { family: root.font; pixelSize: 13; bold: true }
                                }
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: root.evWhenStr(ne.modelData) + "  ·  󰍎 " + ne.modelData.place + (ne.modelData.city && ne.modelData.city !== "Nantes" ? " (" + ne.modelData.city + ")" : "")
                                    color: root.dim
                                    font { family: root.font; pixelSize: 11 }
                                }
                                Row {
                                    spacing: 6
                                    Repeater {
                                        model: ne.modelData.types.slice(0, 2)
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool mu: modelData === "Meetup"
                                            readonly property bool pop: modelData === "Convention" || modelData === "Pop culture"
                                            width: tyT.implicitWidth + 12; height: 16; radius: 8
                                            color: mu ? "#f64060" : pop ? root.accent : root.surface
                                            Text { id: tyT; anchors.centerIn: parent; text: parent.modelData.split(" - ")[0]; color: parent.mu ? "#ffffff" : parent.pop ? root.bg : root.fg; font { family: root.font; pixelSize: 10; bold: parent.mu || parent.pop } }
                                        }
                                    }
                                    Rectangle {
                                        visible: !!ne.modelData.price
                                        width: prT.implicitWidth + 12; height: 16; radius: 8
                                        color: ne.modelData.free ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : root.surface
                                        Text { id: prT; anchors.centerIn: parent; text: ne.modelData.price; color: ne.modelData.free ? root.accent : root.fg; font { family: root.font; pixelSize: 10; bold: ne.modelData.free } }
                                    }
                                    Text {
                                        visible: ne.modelData.more > 0
                                        text: "+" + ne.modelData.more + " date" + (ne.modelData.more > 1 ? "s" : "")
                                        color: root.dim
                                        font { family: root.font; pixelSize: 10 }
                                    }
                                    Text {
                                        visible: (ne.modelData.going ?? 0) > 0
                                        text: ne.modelData.going + " inscrit" + (ne.modelData.going > 1 ? "s" : "")
                                        color: root.dim
                                        font { family: root.font; pixelSize: 10 }
                                    }
                                    // Temps de trajet depuis « home » (à pied · à vélo) ; clic → itinéraire transports
                                    Rectangle {
                                        id: neTr
                                        visible: ne.modelData.walk != null
                                        width: trT.implicitWidth + 12; height: 16; radius: 8
                                        color: neTrHover ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : root.surface
                                        property bool neTrHover: false
                                        Text {
                                            id: trT
                                            anchors.centerIn: parent
                                            text: String.fromCodePoint(0xF0583) + " " + root.evDur(ne.modelData.walk)
                                                  + (ne.modelData.bike != null ? "  " + String.fromCodePoint(0xF00A3) + " " + root.evDur(ne.modelData.bike) : "")
                                            color: parent.neTrHover ? root.accent : root.fg
                                            font { family: root.font; pixelSize: 10 }
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                id: neMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                function onTravel(x, y) { const p = neTr.mapFromItem(neMa, x, y); return neTr.visible && !!ne.modelData.route && neTr.contains(p) }
                                onPositionChanged: m => neTr.neTrHover = onTravel(m.x, m.y)
                                onExited: neTr.neTrHover = false
                                onClicked: m => root.openUrl(onTravel(m.x, m.y) ? ne.modelData.route : ne.modelData.link)
                            }
                        }
                    }
                }
            }

            // ============ Onglet : Nantes ============
            Row {
                id: naTab
                visible: root.dashTab === "nantes"
                spacing: 12
                readonly property var n: root.naolib
                readonly property color red: root.wal ? root.wal.colors.color1 : "#ed8796"
                readonly property color green: root.wal ? root.wal.colors.color2 : "#a6da95"

                component LineBadge: Rectangle {
                    property string line
                    property string bg: "#888888"
                    property string fgc: "#ffffff"
                    width: Math.max(24, lbT.implicitWidth + 10); height: 20; radius: 6
                    color: bg
                    Text { id: lbT; anchors.centerIn: parent; text: parent.line; color: parent.fgc; font { family: root.font; pixelSize: 11; bold: true } }
                }

                Column {
                    spacing: 12

                    // Prochains passages
                    DashCard {
                        width: 320; height: 300
                        Text {
                            id: psTitle
                            anchors { left: parent.left; top: parent.top; margins: 18 }
                            text: "󰃧  " + (naTab.n?.stops?.[0]?.name ?? "Prochains passages")
                            color: root.accent
                            font { family: root.font; pixelSize: 15; bold: true }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: 18; verticalCenter: psTitle.verticalCenter }
                            visible: !naolibProc.running
                            text: "󰀠 live"
                            color: naTab.green
                            font { family: root.font; pixelSize: 11 }
                        }
                        Orb { look: "waiting"; size: 18; color: root.accent; visible: naolibProc.running; anchors { right: parent.right; rightMargin: 18; verticalCenter: psTitle.verticalCenter } }
                        Text {
                            anchors { left: parent.left; right: parent.right; top: psTitle.bottom; margins: 18; topMargin: 12 }
                            visible: !naTab.n || !!naTab.n.error || !(naTab.n.stops ?? []).length
                            wrapMode: Text.WordWrap
                            text: !naTab.n ? "Chargement…" : naTab.n.error ? "󰀦 " + naTab.n.error
                                  : "Choisis tes arrêts : naolib-fetch --set \"Commerce\" \"…\""
                            color: root.dim
                            font { family: root.font; pixelSize: 11 }
                        }
                        ListView {
                            anchors { left: parent.left; right: parent.right; top: psTitle.bottom; bottom: parent.bottom; margins: 12; topMargin: 10 }
                            clip: true
                            spacing: 2
                            model: naTab.n?.stops?.[0]?.lines ?? []
                            delegate: Item {
                                id: ps
                                required property var modelData
                                width: ListView.view.width; height: 30
                                LineBadge {
                                    id: psB
                                    anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                                    line: ps.modelData.line; bg: ps.modelData.color; fgc: ps.modelData.text
                                }
                                Text {
                                    anchors { left: psB.right; leftMargin: 8; right: psTimes.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    elide: Text.ElideRight
                                    text: ps.modelData.headsign
                                    color: root.fg
                                    font { family: root.font; pixelSize: 12 }
                                }
                                Row {
                                    id: psTimes
                                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                    spacing: 8
                                    Repeater {
                                        model: ps.modelData.times
                                        delegate: Text {
                                            required property var modelData
                                            required property int index
                                            readonly property int m: Math.max(0, Math.round((modelData.ts * 1000 - dash.now.getTime()) / 60000))
                                            text: m === 0 ? "proche" : m + (index === 0 ? " min" : "")
                                            color: modelData.rt ? naTab.green : root.dim
                                            font { family: root.font; pixelSize: index === 0 ? 13 : 11; bold: index === 0 }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Info trafic
                    DashCard {
                        width: 320; height: 288
                        readonly property var alerts: naTab.n?.alerts ?? []
                        Text {
                            id: itTitle
                            anchors { left: parent.left; top: parent.top; margins: 18 }
                            text: "󰀦  Info trafic"
                            color: root.accent
                            font { family: root.font; pixelSize: 15; bold: true }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: 18; verticalCenter: itTitle.verticalCenter }
                            text: parent.alerts.filter(a => a.mine).length + " sur tes lignes · " + parent.alerts.length
                            color: root.dim
                            font { family: root.font; pixelSize: 10 }
                        }
                        ListView {
                            anchors { left: parent.left; right: parent.right; top: itTitle.bottom; bottom: parent.bottom; margins: 12; topMargin: 10 }
                            clip: true
                            spacing: 4
                            model: parent.alerts
                            delegate: Rectangle {
                                id: al
                                required property var modelData
                                property bool open: false
                                width: ListView.view.width; height: alCol.implicitHeight + 14; radius: 10
                                color: alMa.containsMouse || open ? root.surface : al.modelData.mine ? Qt.rgba(naTab.red.r, naTab.red.g, naTab.red.b, 0.10) : "transparent"
                                Column {
                                    id: alCol
                                    anchors { left: parent.left; right: parent.right; margins: 8; verticalCenter: parent.verticalCenter }
                                    spacing: 4
                                    Flow {
                                        width: parent.width
                                        spacing: 4
                                        Repeater {
                                            model: al.modelData.lines.slice(0, 6)
                                            delegate: LineBadge { required property var modelData; line: modelData.line; bg: modelData.color; fgc: modelData.text }
                                        }
                                    }
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.WordWrap; maximumLineCount: al.open ? 3 : 2; elide: Text.ElideRight
                                        text: al.modelData.title
                                        color: root.fg
                                        font { family: root.font; pixelSize: 12; bold: al.modelData.mine }
                                    }
                                    Text {
                                        width: parent.width
                                        visible: al.open
                                        wrapMode: Text.WordWrap; maximumLineCount: 10; elide: Text.ElideRight
                                        text: al.modelData.desc
                                        color: root.dim
                                        font { family: root.font; pixelSize: 11 }
                                    }
                                }
                                MouseArea { id: alMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: al.open = !al.open }
                            }
                        }
                    }
                }

                // Carte + itinéraires
                DashCard {
                    id: nmap
                    width: 672; height: 600
                    clip: true
                    readonly property var m: root.naoMap
                    readonly property real k: Math.cos(47.218 * Math.PI / 180)
                    property real vs: 0
                    property real vx: 0
                    property real vy: 0
                    property var hover: null
                    function px(lat, lon) { return [vs * lon * k + vx, vs * -lat + vy] }
                    // Carte à tuiles (NaoMap.qml, QtLocation) si disponible, sinon dessin sur Canvas ci-dessous
                    readonly property bool tiled: tileMap.status === Loader.Ready
                    function fitTo(pts, pad) {
                        if (tiled) { tileMap.item.fitTo(pts, pad); return }
                        if (!pts.length) return
                        let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9
                        for (const p of pts) { x0 = Math.min(x0, p[1] * k); x1 = Math.max(x1, p[1] * k); y0 = Math.min(y0, -p[0]); y1 = Math.max(y1, -p[0]) }
                        const s = Math.min((width - 2 * pad) / Math.max(1e-6, x1 - x0), (height - 2 * pad) / Math.max(1e-6, y1 - y0))
                        vs = s; vx = (width - s * (x1 - x0)) / 2 - s * x0; vy = (height - s * (y1 - y0)) / 2 - s * y0 + 20
                        base.requestPaint(); live.requestPaint()
                    }
                    function fitNetwork() {
                        if (tiled) { tileMap.item.fitNetwork(); return }
                        if (!m) return
                        const pts = []
                        for (const l of m.lines) for (const path of l.paths) for (const p of path) pts.push(p)
                        fitTo(pts, 40)
                    }
                    onMChanged: fitNetwork()
                    Component.onCompleted: fitNetwork()
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

                    Loader {
                        id: tileMap
                        anchors.fill: parent
                        source: "NaoMap.qml"
                        asynchronous: true
                    }
                    // Fond : eau, parcs, routes, lignes, arrêts, quartiers (redessiné au zoom / déplacement)
                    Canvas {
                        id: base
                        anchors.fill: parent
                        visible: !nmap.tiled
                        onPaint: {
                            const ctx = getContext("2d"), m = nmap.m
                            ctx.reset()
                            if (!m || !nmap.vs) return
                            const P = (a, b) => nmap.px(a, b)
                            const poly = (pts, close) => {
                                ctx.beginPath()
                                for (let i = 0; i < pts.length; i++) { const q = P(pts[i][0], pts[i][1]); i ? ctx.lineTo(q[0], q[1]) : ctx.moveTo(q[0], q[1]) }
                                if (close) ctx.closePath()
                            }
                            const wal = root.wal ? root.wal.colors : null
                            const water = wal ? Qt.color(wal.color6) : Qt.color("#7dc4e4")
                            const green = wal ? Qt.color(wal.color2) : Qt.color("#a6da95")
                            ctx.fillStyle = root.rgba(green, 0.08)
                            for (const g of m.parks) { poly(g, true); ctx.fill() }
                            ctx.fillStyle = root.rgba(water, 0.20)
                            for (const g of m.water) { poly(g, true); ctx.fill() }
                            ctx.strokeStyle = root.rgba(water, 0.30); ctx.lineWidth = 1.2
                            for (const g of m.rivers) { poly(g, false); ctx.stroke() }
                            ctx.lineCap = "round"; ctx.lineJoin = "round"
                            const z = nmap.vs / 4000
                            for (let c = 2; c >= 0; c--) {
                                if (c === 2 && z < 1.6) continue
                                ctx.strokeStyle = root.rgba(root.fg, [0.16, 0.11, 0.07][c]); ctx.lineWidth = [2.2, 1.5, 1][c] * Math.min(2, Math.max(1, z / 2))
                                for (const g of m.roads[c]) { poly(g, false); ctx.stroke() }
                            }
                            for (const l of m.lines.slice().reverse()) {
                                ctx.strokeStyle = l.color; ctx.globalAlpha = l.type === 0 ? 0.9 : 0.55
                                ctx.lineWidth = (l.type === 0 ? 3.5 : 2.2) * Math.min(2, Math.max(1, z / 2))
                                for (const g of l.paths) { poly(g, false); ctx.stroke() }
                            }
                            ctx.globalAlpha = 1
                            for (const s of m.stops) {
                                const q = P(s[1], s[2])
                                ctx.fillStyle = root.rgba(root.bg, 1); ctx.beginPath(); ctx.arc(q[0], q[1], 2.6, 0, 7); ctx.fill()
                                ctx.strokeStyle = root.rgba(root.fg, 0.9); ctx.lineWidth = 1; ctx.stroke()
                            }
                            ctx.font = "600 10px '" + root.font + "'"; ctx.textAlign = "center"
                            for (const pl of m.places) {
                                if (pl[3] > (z > 3 ? 2 : z > 1.5 ? 1 : 0)) continue
                                const q = P(pl[1], pl[2])
                                if (q[0] < 0 || q[1] < 0 || q[0] > width || q[1] > height) continue
                                ctx.fillStyle = root.rgba(root.fg, pl[3] === 0 ? 0.45 : 0.30)
                                ctx.fillText(pl[0].toUpperCase(), q[0], q[1])
                            }
                            if (z > 3) {
                                ctx.textAlign = "left"; ctx.font = "500 10px '" + root.font + "'"; ctx.fillStyle = root.rgba(root.fg, 0.6)
                                for (const s of m.stops) { const q = P(s[1], s[2]); ctx.fillText(s[0], q[0] + 5, q[1] - 4) }
                            }
                        }
                    }
                    // Véhicules + itinéraire choisi (redessinés chaque seconde)
                    Canvas {
                        id: live
                        anchors.fill: parent
                        visible: !nmap.tiled
                        Timer { interval: 1000; repeat: true; running: naTab.visible && !nmap.tiled; onTriggered: live.requestPaint() }
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            if (!nmap.vs) return
                            const now = Date.now() / 1000
                            const r = root.route?.routes?.[root.routeSel]
                            if (r && r.path.length) {
                                ctx.lineCap = "round"; ctx.lineJoin = "round"
                                for (const [w, c] of [[8, root.rgba(root.bg, 0.9)], [5, root.rgba(root.accent, 1)]]) {
                                    ctx.strokeStyle = c; ctx.lineWidth = w; ctx.beginPath()
                                    r.path.forEach((p, i) => { const q = nmap.px(p[0], p[1]); i ? ctx.lineTo(q[0], q[1]) : ctx.moveTo(q[0], q[1]) })
                                    ctx.stroke()
                                }
                                for (const p of [r.path[0], r.path[r.path.length - 1]]) {
                                    const q = nmap.px(p[0], p[1])
                                    ctx.fillStyle = root.rgba(root.accent, 1); ctx.beginPath(); ctx.arc(q[0], q[1], 7, 0, 7); ctx.fill()
                                    ctx.fillStyle = root.rgba(root.bg, 1); ctx.beginPath(); ctx.arc(q[0], q[1], 3, 0, 7); ctx.fill()
                                }
                            }
                            const vs = []
                            for (const v of naTab.n?.vehicles ?? []) {
                                const q = nmap.pos(v, now)
                                if (!q) continue
                                const xy = nmap.px(q.lat, q.lon), tram = v.type === 0, rad = tram ? 8 : 6.5
                                vs.push({ v: v, q: q, x: xy[0], y: xy[1] })
                                ctx.fillStyle = v.color; ctx.beginPath(); ctx.arc(xy[0], xy[1], rad, 0, 7); ctx.fill()
                                ctx.lineWidth = 1.8; ctx.strokeStyle = v.rt ? root.rgba(naTab.green, 1) : root.rgba(root.bg, 1); ctx.stroke()
                                ctx.fillStyle = v.text; ctx.font = "700 " + (tram ? 9 : 7) + "px '" + root.font + "'"
                                ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(v.line, xy[0], xy[1] + 0.5)
                            }
                            nmap.vehiclesNow = vs
                        }
                    }
                    property var vehiclesNow: []

                    // Glisser = déplacer, molette = zoomer, survol = infos du véhicule
                    MouseArea {
                        anchors.fill: parent
                        enabled: !nmap.tiled
                        visible: enabled
                        hoverEnabled: true
                        property real lx: 0
                        property real ly: 0
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPressed: m => { lx = m.x; ly = m.y; searchTo.focus = false; searchFrom.focus = false }
                        onPositionChanged: m => {
                            if (pressed) {
                                nmap.vx += m.x - lx; nmap.vy += m.y - ly; lx = m.x; ly = m.y
                                base.requestPaint(); live.requestPaint(); nmap.hover = null
                            } else {
                                nmap.hover = nmap.vehiclesNow.find(v => Math.hypot(v.x - m.x, v.y - m.y) < 9) ?? null
                            }
                        }
                        onExited: nmap.hover = null
                        onWheel: w => {
                            const f = w.angleDelta.y > 0 ? 1.18 : 1 / 1.18
                            nmap.vx = w.x - (w.x - nmap.vx) * f; nmap.vy = w.y - (w.y - nmap.vy) * f; nmap.vs *= f
                            base.requestPaint(); live.requestPaint()
                        }
                    }
                    Rectangle {
                        visible: !!nmap.hover && !nmap.tiled
                        x: Math.min((nmap.hover?.x ?? 0) + 12, nmap.width - width - 8); y: (nmap.hover?.y ?? 0) + 12
                        width: hvCol.implicitWidth + 20; height: hvCol.implicitHeight + 14; radius: 10
                        color: root.bg
                        border { width: 1; color: root.surface }
                        Column {
                            id: hvCol
                            anchors.centerIn: parent
                            Text { text: "Ligne " + (nmap.hover?.v.line ?? "") + " → " + (nmap.hover?.v.headsign ?? ""); color: root.fg; font { family: root.font; pixelSize: 12; bold: true } }
                            Text { text: "Prochain arrêt : " + (nmap.hover?.q.next ?? ""); color: root.dim; font { family: root.font; pixelSize: 11 } }
                            Text { text: nmap.hover?.v.rt ? "position recalée en temps réel" : "horaire théorique"; color: nmap.hover?.v.rt ? naTab.green : root.dim; font { family: root.font; pixelSize: 10 } }
                        }
                    }

                    // Barre de recherche d'itinéraire
                    Rectangle {
                        id: search
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        height: 44; radius: 22
                        color: root.bg
                        border { width: 1; color: root.surface }
                        Row {
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "󰍎"; color: root.accent; font { family: root.font; pixelSize: 15 } }
                            TextInput {
                                id: searchFrom
                                anchors.verticalCenter: parent.verticalCenter
                                width: 150; clip: true
                                color: root.fg; selectionColor: root.accent
                                font { family: root.font; pixelSize: 12 }
                                Text { visible: !parent.text && !parent.activeFocus; text: "Départ"; color: root.dim; font: parent.font }
                                onAccepted: searchTo.forceActiveFocus()
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "󰁔"; color: root.dim; font { family: root.font; pixelSize: 13 } }
                            TextInput {
                                id: searchTo
                                anchors.verticalCenter: parent.verticalCenter
                                width: 190; clip: true
                                color: root.fg; selectionColor: root.accent
                                font { family: root.font; pixelSize: 12 }
                                Text { visible: !parent.text && !parent.activeFocus; text: "Où veux-tu aller ?"; color: root.dim; font: parent.font }
                                onAccepted: root.findRoute(searchFrom.text, searchTo.text)
                            }
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Repeater {
                                model: [["transit", "󰃧"], ["drive", "󰄋"], ["bicycle", "󰂣"], ["walk", "󰖃"]]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root.routeMode === modelData[0]
                                    width: 32; height: 32; radius: 16
                                    color: sel ? root.surface : "transparent"
                                    Text { anchors.centerIn: parent; text: parent.modelData[1]; color: parent.sel ? root.accent : root.dim; font { family: root.font; pixelSize: 15 } }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.routeMode = parent.modelData[0]; if (searchTo.text) root.findRoute(searchFrom.text, searchTo.text) }
                                    }
                                }
                            }
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: root.accent
                                Text {
                                    anchors.centerIn: parent
                                    visible: !routeProc.running
                                    text: "󰍉"
                                    color: root.bg
                                    font { family: root.font; pixelSize: 15 }
                                }
                                Orb { look: "searching"; size: 24; color: root.bg; visible: routeProc.running; anchors.centerIn: parent }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.findRoute(searchFrom.text, searchTo.text) }
                            }
                        }
                    }

                    // Résultats
                    Rectangle {
                        id: results
                        visible: !!root.route
                        anchors { left: parent.left; top: search.bottom; leftMargin: 14; topMargin: 10 }
                        width: 300; height: Math.min(resCol.implicitHeight + 24, nmap.height - search.height - 40)
                        radius: 18
                        color: root.bg
                        border { width: 1; color: root.surface }
                        clip: true
                        Flickable {
                            anchors { fill: parent; margins: 12 }
                            contentHeight: resCol.implicitHeight
                            clip: true
                            Column {
                                id: resCol
                                width: parent.width
                                spacing: 6
                                Item {
                                    width: parent.width; height: 20
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (root.route?.routes?.length ?? 0) + " itinéraire" + ((root.route?.routes?.length ?? 0) > 1 ? "s" : "")
                                        color: root.dim
                                        font { family: root.font; pixelSize: 11 }
                                    }
                                    Text {
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        text: "󰅖"
                                        color: root.dim
                                        font { family: root.font; pixelSize: 13 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.route = null; nmap.fitNetwork() } }
                                    }
                                }
                                Text {
                                    width: parent.width
                                    visible: !!root.route?.error
                                    wrapMode: Text.WordWrap
                                    text: root.route?.error === "nokey"
                                          ? "Pas encore de clé Google Maps : ajoute-la dans ~/.config/quickshell/google-maps.key pour voir les trajets ici."
                                          : "󰀦 " + (root.route?.error ?? "")
                                    color: root.dim
                                    font { family: root.font; pixelSize: 11 }
                                }
                                Repeater {
                                    model: root.route?.routes ?? []
                                    delegate: Rectangle {
                                        id: rt
                                        required property var modelData
                                        required property int index
                                        readonly property bool sel: root.routeSel === index
                                        width: resCol.width; height: rtCol.implicitHeight + 16; radius: 12
                                        color: sel ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : rtMa.containsMouse ? root.surface : "transparent"
                                        border { width: sel ? 1 : 0; color: root.accent }
                                        Column {
                                            id: rtCol
                                            anchors { left: parent.left; right: parent.right; margins: 10; verticalCenter: parent.verticalCenter }
                                            spacing: 6
                                            Item {
                                                width: parent.width; height: 22
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: rt.modelData.dep + " → " + rt.modelData.arr
                                                    color: root.fg
                                                    font { family: root.font; pixelSize: 13; bold: true }
                                                }
                                                Text {
                                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                                    text: root.durStr(rt.modelData.duration)
                                                    color: root.accent
                                                    font { family: root.font; pixelSize: 14; bold: true }
                                                }
                                            }
                                            Flow {
                                                width: parent.width
                                                spacing: 4
                                                Repeater {
                                                    model: rt.modelData.steps
                                                    delegate: Loader {
                                                        required property var modelData
                                                        sourceComponent: modelData.kind === "transit" ? transitStep : otherStep
                                                        Component {
                                                            id: transitStep
                                                            LineBadge { line: modelData.line; bg: modelData.color; fgc: modelData.text }
                                                        }
                                                        Component {
                                                            id: otherStep
                                                            Rectangle {
                                                                width: osT.implicitWidth + 10; height: 20; radius: 6
                                                                color: root.surface
                                                                Text {
                                                                    id: osT
                                                                    anchors.centerIn: parent
                                                                    text: ({ walk: "󰖃", drive: "󰄋", bicycle: "󰂣" }[modelData.kind] ?? "•") + " " + Math.max(1, Math.round(modelData.duration / 60))
                                                                    color: root.fg
                                                                    font { family: root.font; pixelSize: 10 }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            Text {
                                                width: parent.width
                                                visible: rt.sel
                                                wrapMode: Text.WordWrap
                                                text: rt.modelData.steps.filter(s => s.kind === "transit")
                                                        .map(s => s.line + " " + s.dep + " à " + s.from + " → " + s.to + " (" + s.stops + " arrêts)").join("\n")
                                                      || ((rt.modelData.distance / 1000).toFixed(1).replace(".", ",") + " km" + (rt.modelData.summary ? " · par " + rt.modelData.summary : ""))
                                                color: root.dim
                                                font { family: root.font; pixelSize: 10 }
                                            }
                                        }
                                        MouseArea {
                                            id: rtMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { root.routeSel = rt.index; nmap.fitTo(rt.modelData.path, 60) }
                                        }
                                    }
                                }
                                Text {
                                    text: "Ouvrir dans Google Maps 󰁔"
                                    color: gmMa.containsMouse ? root.accent : root.dim
                                    font { family: root.font; pixelSize: 11; bold: true }
                                    topPadding: 4
                                    MouseArea { id: gmMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openUrl(root.route.mapsUrl) }
                                }
                            }
                        }
                    }
                    Connections {
                        target: root
                        function onRouteChanged() { const r = root.route?.routes?.[0]; if (r) nmap.fitTo(r.path, 60) }
                    }

                    // Légende et zoom
                    Text {
                        anchors { left: parent.left; bottom: parent.bottom; margins: 16 }
                        text: (nmap.tiled ? tileMap.item.count : nmap.vehiclesNow.length) + " véhicules · positions estimées (horaires + retards temps réel)"
                        color: root.dim
                        font { family: root.font; pixelSize: 10 }
                    }
                    Column {
                        anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
                        spacing: 6
                        Repeater {
                            model: [["󰐕", 1.3], ["󰍴", 1 / 1.3], ["󰆾", 0]]
                            delegate: Rectangle {
                                required property var modelData
                                width: 32; height: 32; radius: 12
                                color: zMa.containsMouse ? root.accent : root.bg
                                Text { anchors.centerIn: parent; text: parent.modelData[0]; color: zMa.containsMouse ? root.bg : root.fg; font { family: root.font; pixelSize: 14 } }
                                MouseArea {
                                    id: zMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const f = parent.modelData[1]
                                        if (!f) { nmap.fitNetwork(); return }
                                        if (nmap.tiled) { tileMap.item.zoomBy(f); return }
                                        nmap.vx = nmap.width / 2 - (nmap.width / 2 - nmap.vx) * f; nmap.vy = nmap.height / 2 - (nmap.height / 2 - nmap.vy) * f; nmap.vs *= f
                                        base.requestPaint(); live.requestPaint()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ============ Onglet : Mises à jour ============
            // En-tête (résumé, actualiser, tout installer) puis maître-détail : sources à gauche,
            // paquets de la source choisie à droite (erreur dans un bandeau séparé, liste défilante).
            Column {
                id: upTab
                visible: root.dashTab === "updates"
                width: 1004
                spacing: 12
                readonly property var u: root.updates
                readonly property var icons: ({ apt: "󰕈", snap: "󰏗", flatpak: "󰏖", brew: "󰂄", firmware: "󰍛", zen: "󰖟" })
                readonly property var sources: u?.sources ?? []
                property string selId: ""
                readonly property var cur: sources.find(s => s.id === selId) ?? sources.find(s => s.count > 0) ?? sources[0] ?? null
                readonly property color red: root.cvssColor(9)
                readonly property color orange: root.cvssColor(7)
                function secCount(s) { return (s?.items ?? []).filter(i => i.security).length }
                function kernel(i) { return /^linux-(image|headers|modules|generic|tools|hwe)/.test(i.name) || /^linux-generic/.test(i.name) }
                function subtitle(s) {
                    if (!s) return ""
                    const sec = secCount(s)
                    return s.count ? s.count + " mise" + (s.count > 1 ? "s" : "") + " à jour" + (sec ? "  ·  " + sec + " sécurité" : "")
                                   : s.error ? "Vérification impossible" : "À jour"
                }

                // ---- Résumé
                DashCard {
                    width: parent.width; height: 96
                    Rectangle {
                        id: upIcon
                        anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                        width: 56; height: 56; radius: 18
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                        Text {
                            anchors.centerIn: parent
                            text: root.updCount ? "󰚰" : "󰄬"
                            color: root.accent
                            font { family: root.font; pixelSize: 26 }
                        }
                    }
                    Column {
                        anchors { left: upIcon.right; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 3
                        Text {
                            text: !upTab.u ? "Recherche des mises à jour…"
                                : root.updCount ? root.updCount + " mise" + (root.updCount > 1 ? "s" : "") + " à jour disponible" + (root.updCount > 1 ? "s" : "")
                                : "Tout est à jour"
                            color: root.fg
                            font { family: root.font; pixelSize: 18; bold: true }
                        }
                        Text {
                            text: [upTab.u?.reboot ? "󰜉 redémarrage nécessaire" : "",
                                   upTab.u?.aptAge ? "listes apt du " + new Date(upTab.u.aptAge * 1000).toLocaleString(Qt.locale("fr_FR"), "d MMM 'à' HH:mm") : "",
                                   upTab.u?.ts ? "vérifié il y a " + root.agoStr(upTab.u.ts) : ""].filter(x => x).join("  ·  ")
                            color: upTab.u?.reboot ? upTab.orange : root.dim
                            font { family: root.font; pixelSize: 12 }
                        }
                    }
                    Row {
                        anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Rectangle {
                            width: 40; height: 40; radius: 20
                            color: upRefMa.containsMouse ? root.surface : "transparent"
                            Text {
                                anchors.centerIn: parent
                                visible: !updProc.running
                                text: "󰑐"
                                color: root.dim
                                font { family: root.font; pixelSize: 17 }
                            }
                            Orb { look: "working"; size: 24; color: root.accent; visible: updProc.running; anchors.centerIn: parent }
                            MouseArea { id: upRefMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!updProc.running) { updProc.force = true; updProc.running = true } }
                        }
                        Rectangle {
                            visible: root.updCount > 0
                            width: upAllT.implicitWidth + 32; height: 40; radius: 20
                            color: upAllMa.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent
                            Text {
                                id: upAllT
                                anchors.centerIn: parent
                                text: "󰚰  Tout mettre à jour"
                                color: root.bg
                                font { family: root.font; pixelSize: 13; bold: true }
                            }
                            MouseArea {
                                id: upAllMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runUpdate(upTab.sources.filter(s => s.count).map(s => s.id))
                            }
                        }
                    }
                }

                Row {
                    visible: !!upTab.u
                    spacing: 12
                    height: 504

                    // ---- Sources
                    DashCard {
                        width: 300; height: parent.height
                        Column {
                            anchors { fill: parent; margins: 10 }
                            spacing: 4
                            Repeater {
                                model: upTab.sources
                                delegate: Rectangle {
                                    id: srcRow
                                    required property var modelData
                                    readonly property bool sel: upTab.cur?.id === modelData.id
                                    readonly property bool err: !!modelData.error
                                    width: parent.width; height: 70; radius: 16
                                    color: sel ? root.surface : srMa.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Rectangle {
                                        visible: srcRow.sel
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        width: 4; height: 30; radius: 2
                                        color: root.accent
                                    }
                                    Rectangle {
                                        id: srIcon
                                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                        width: 42; height: 42; radius: 14
                                        color: srcRow.modelData.count ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                                                                      : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                                        Text {
                                            anchors.centerIn: parent
                                            text: upTab.icons[srcRow.modelData.id] ?? "󰏗"
                                            color: srcRow.modelData.count ? root.accent : root.dim
                                            font { family: root.font; pixelSize: 20 }
                                        }
                                    }
                                    Column {
                                        anchors { left: srIcon.right; leftMargin: 12; right: srBadge.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        spacing: 3
                                        Text {
                                            width: parent.width; elide: Text.ElideRight
                                            text: srcRow.modelData.name
                                            color: root.fg
                                            font { family: root.font; pixelSize: 13; bold: true }
                                        }
                                        Text {
                                            width: parent.width; elide: Text.ElideRight
                                            // compact : le nombre total est déjà dans la pastille
                                            text: srcRow.err ? "󰀦 Vérification impossible"
                                                : upTab.secCount(srcRow.modelData) ? "󰒃 " + upTab.secCount(srcRow.modelData) + " de sécurité"
                                                : upTab.subtitle(srcRow.modelData)
                                            color: srcRow.err ? upTab.red : upTab.secCount(srcRow.modelData) ? upTab.orange : root.dim
                                            font { family: root.font; pixelSize: 11 }
                                        }
                                    }
                                    Rectangle {
                                        id: srBadge
                                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                        width: Math.max(26, srBadgeT.implicitWidth + 14); height: 24; radius: 12
                                        color: srcRow.modelData.count ? root.accent : "transparent"
                                        Text {
                                            id: srBadgeT
                                            anchors.centerIn: parent
                                            text: srcRow.modelData.count ? srcRow.modelData.count : srcRow.err ? "󰀦" : "󰄬"
                                            color: srcRow.modelData.count ? root.bg : srcRow.err ? upTab.red : root.dim
                                            font { family: root.font; pixelSize: 11; bold: true }
                                        }
                                    }
                                    MouseArea { id: srMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: upTab.selId = srcRow.modelData.id }
                                }
                            }
                        }
                    }

                    // ---- Détail de la source choisie
                    DashCard {
                        id: upDet
                        readonly property var s: upTab.cur
                        readonly property var items: (s?.items ?? []).slice().sort((a, b) =>
                            (b.security - a.security) || (upTab.kernel(b) - upTab.kernel(a)) || a.name.localeCompare(b.name))
                        width: 692; height: parent.height
                        Item {
                            id: detHead
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                            height: 44
                            Text {
                                id: detIcon
                                anchors.verticalCenter: parent.verticalCenter
                                text: upTab.icons[upDet.s?.id] ?? "󰏗"
                                color: root.accent
                                font { family: root.font; pixelSize: 26 }
                            }
                            Column {
                                anchors { left: detIcon.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Text { text: upDet.s?.name ?? ""; color: root.fg; font { family: root.font; pixelSize: 17; bold: true } }
                                Text { text: upTab.subtitle(upDet.s); color: root.dim; font { family: root.font; pixelSize: 11 } }
                            }
                            Rectangle {
                                visible: (upDet.s?.count ?? 0) > 0
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: detBtnT.implicitWidth + 28; height: 36; radius: 18
                                color: detBtnMa.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent
                                Text {
                                    id: detBtnT
                                    anchors.centerIn: parent
                                    text: "󰁔  Installer " + (upDet.s?.count ?? 0)
                                    color: root.bg
                                    font { family: root.font; pixelSize: 12; bold: true }
                                }
                                MouseArea { id: detBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.runUpdate([upDet.s.id]) }
                            }
                        }
                        // Bandeau d'erreur (séparé de la liste)
                        Rectangle {
                            id: detErr
                            visible: !!upDet.s?.error
                            anchors { left: parent.left; right: parent.right; top: detHead.bottom; margins: 20; topMargin: 14 }
                            height: visible ? detErrT.implicitHeight + 20 : 0
                            radius: 12
                            color: Qt.rgba(upTab.red.r, upTab.red.g, upTab.red.b, 0.14)
                            Text {
                                id: detErrT
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                                wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight
                                text: "󰀦  Dernière vérification en échec" + ((upDet.s?.count ?? 0) ? " (liste ci-dessous issue du cache)" : "") + " : " + (upDet.s?.error ?? "")
                                color: upTab.red
                                font { family: root.font; pixelSize: 11 }
                            }
                        }
                        // En-têtes de colonnes
                        Item {
                            id: detCols
                            visible: upDet.items.length > 0
                            anchors { left: parent.left; right: parent.right; top: detErr.visible ? detErr.bottom : detHead.bottom; margins: 20; topMargin: 14 }
                            height: 18
                            Text { x: 12; text: "PAQUET"; color: root.dim; font { family: root.font; pixelSize: 10; bold: true; letterSpacing: 1 } }
                            Text { x: 346; text: "INSTALLÉE"; color: root.dim; font { family: root.font; pixelSize: 10; bold: true; letterSpacing: 1 } }
                            Text { x: 492; text: "DISPONIBLE"; color: root.dim; font { family: root.font; pixelSize: 10; bold: true; letterSpacing: 1 } }
                        }
                        ListView {
                            id: detList
                            anchors { left: parent.left; right: parent.right; top: detCols.bottom; bottom: parent.bottom; margins: 14; topMargin: 6; leftMargin: 20; rightMargin: 20 }
                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            model: upDet.items
                            delegate: Rectangle {
                                id: pkg
                                required property var modelData
                                required property int index
                                width: ListView.view.width; height: 34; radius: 10
                                color: pkMa.containsMouse ? root.surface : index % 2 ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03) : "transparent"
                                Row {
                                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    width: 318
                                    spacing: 6
                                    Text {
                                        width: Math.min(implicitWidth, 318 - (pkSec.visible ? pkSec.width + 6 : 0) - (pkKer.visible ? pkKer.width + 6 : 0))
                                        elide: Text.ElideRight
                                        text: pkg.modelData.name
                                        color: root.fg
                                        font { family: root.font; pixelSize: 12 }
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Rectangle {
                                        id: pkSec
                                        visible: !!pkg.modelData.security
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: pkSecT.implicitWidth + 12; height: 16; radius: 8
                                        color: Qt.rgba(upTab.orange.r, upTab.orange.g, upTab.orange.b, 0.2)
                                        Text { id: pkSecT; anchors.centerIn: parent; text: "󰒃 sécurité"; color: upTab.orange; font { family: root.font; pixelSize: 9; bold: true } }
                                    }
                                    Rectangle {
                                        id: pkKer
                                        visible: upDet.s?.id === "apt" && upTab.kernel(pkg.modelData)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: pkKerT.implicitWidth + 12; height: 16; radius: 8
                                        color: root.surface
                                        Text { id: pkKerT; anchors.centerIn: parent; text: "noyau"; color: root.fg; font { family: root.font; pixelSize: 9 } }
                                    }
                                }
                                Text {
                                    x: 346; width: 120; elide: Text.ElideMiddle
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pkg.modelData.from || "—"
                                    color: root.dim
                                    font { family: root.font; pixelSize: 11 }
                                }
                                Text {
                                    x: 472
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰁔"
                                    color: root.dim
                                    font { family: root.font; pixelSize: 11 }
                                }
                                Text {
                                    x: 492; width: parent.width - 500; elide: Text.ElideMiddle
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pkg.modelData.to || "—"
                                    color: root.accent
                                    font { family: root.font; pixelSize: 11; bold: true }
                                }
                                MouseArea { id: pkMa; anchors.fill: parent; hoverEnabled: true }
                            }
                        }
                        // Rien à installer
                        Column {
                            visible: !upDet.items.length
                            anchors.centerIn: parent
                            spacing: 8
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: upDet.s?.error ? "󰀦" : "󰄬"; color: upDet.s?.error ? upTab.red : root.accent; font { family: root.font; pixelSize: 44 } }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: upDet.s?.error ? "Impossible de vérifier cette source" : "Rien à installer"; color: root.dim; font { family: root.font; pixelSize: 13 } }
                        }
                    }
                }
            }

            // ============ Onglet : Météo ============
            Column {
                visible: root.dashTab === "weather"
                width: 1004
                spacing: 12

                Row {
                    visible: !dash.w || !!dash.w.error
                    spacing: 14
                    Orb { look: "working"; size: 40; color: root.accent; visible: !dash.w; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: dash.w?.error ?? "Chargement de la météo…"
                        color: root.dim
                        font { family: root.font; pixelSize: 14 }
                    }
                }

                // Maintenant
                DashCard {
                    visible: !!dash.w?.name && !root.weatherMapFull
                    width: parent.width; height: 170
                    Row {
                        anchors { left: parent.left; leftMargin: 32; verticalCenter: parent.verticalCenter }
                        spacing: 24
                        Text { anchors.verticalCenter: parent.verticalCenter; text: dash.w?.icon ?? ""; color: root.accent; font { family: root.font; pixelSize: 96 } }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text { text: (dash.w?.temp ?? "") + "°C"; color: root.fg; font { family: root.font; pixelSize: 48; bold: true } }
                            Text { text: (dash.w?.desc ?? "") + "  ·  " + (dash.w?.name ?? ""); color: root.dim; font { family: root.font; pixelSize: 15 } }
                        }
                    }
                    Grid {
                        anchors { right: parent.right; rightMargin: 36; verticalCenter: parent.verticalCenter }
                        columns: 3
                        columnSpacing: 40
                        rowSpacing: 14
                        Repeater {
                            model: [
                                ["󰔏", "Ressenti", (dash.w?.feels ?? "") + "°C"],
                                ["󰖎", "Humidité", (dash.w?.humidity ?? "") + " %"],
                                ["󰖝", "Vent", (dash.w?.wind ?? "") + " km/h"],
                                ["󰔄", "Min / max", (dash.w?.min ?? "") + "° / " + (dash.w?.max ?? "") + "°"],
                                ["󰖜", "Lever", dash.w?.sunrise ?? ""],
                                ["󰖛", "Coucher", dash.w?.sunset ?? ""]
                            ].concat(root.weatherMap?.here?.air ? [
                                // indice européen de qualité de l'air (weather-map-fetch, heure en cours)
                                ["󰌪", "Qualité de l'air", root.weatherMap.here.air[0] + " · " + root.aqiLabel(root.weatherMap.here.air[0])],
                                ["󰂷", "PM2.5", Math.round(root.weatherMap.here.pm25[0]) + " µg/m³"]
                            ] : [])
                            delegate: Row {
                                required property var modelData
                                spacing: 10
                                Text { text: parent.modelData[0]; color: root.accent; font { family: root.font; pixelSize: 18 } }
                                Column {
                                    Text { text: parent.parent.modelData[1]; color: root.dim; font { family: root.font; pixelSize: 11 } }
                                    Text { text: parent.parent.modelData[2]; color: root.fg; font { family: root.font; pixelSize: 14; bold: true } }
                                }
                            }
                        }
                    }
                }

                // Heure par heure
                DashCard {
                    visible: !!dash.w?.hourly && !root.weatherMapFull
                    width: parent.width; height: 140
                    ListView {
                        anchors { fill: parent; margins: 16 }
                        orientation: ListView.Horizontal
                        spacing: 6
                        clip: true
                        model: dash.w?.hourly ?? []
                        delegate: Column {
                            required property var modelData
                            width: 62
                            spacing: 6
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.time; color: root.dim; font { family: root.font; pixelSize: 12 } }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; color: root.accent; font { family: root.font; pixelSize: 24 } }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp + "°"; color: root.fg; font { family: root.font; pixelSize: 14; bold: true } }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰖌 " + modelData.rain + "%"; color: root.dim; font { family: root.font; pixelSize: 10 } }
                        }
                    }
                }

                // 7 jours (compact) + carte météo
                Row {
                    spacing: 12
                    DashCard {
                        visible: !!dash.w?.daily && !root.weatherMapFull
                        width: 400
                        height: daysCol.implicitHeight + 28
                        Column {
                            id: daysCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            Repeater {
                                model: dash.w?.daily ?? []
                                delegate: Item {
                                    required property var modelData
                                    width: daysCol.width
                                    height: 40
                                    // Échelle commune de la semaine pour les barres min–max
                                    readonly property real lo: Math.min(...dash.w.daily.map(d => d.min))
                                    readonly property real hi: Math.max(...dash.w.daily.map(d => d.max))
                                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData.day; color: root.fg; font { family: root.font; pixelSize: 14; bold: true } }
                                    Text { x: 62; anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; color: root.accent; font { family: root.font; pixelSize: 22 } }
                                    Text { x: 96; anchors.verticalCenter: parent.verticalCenter; text: "󰖌 " + modelData.rain + " %"; color: root.dim; font { family: root.font; pixelSize: 11 } }
                                    Text { x: 160; width: 32; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: modelData.min + "°"; color: root.dim; font { family: root.font; pixelSize: 13 } }
                                    Rectangle {
                                        x: 204; width: 112; height: 6; radius: 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: root.surface
                                        Rectangle {
                                            x: parent.width * (modelData.min - lo) / Math.max(1, hi - lo)
                                            width: parent.width * (modelData.max - modelData.min) / Math.max(1, hi - lo)
                                            height: parent.height; radius: 3
                                            color: root.accent
                                        }
                                    }
                                    Text { x: 328; anchors.verticalCenter: parent.verticalCenter; text: modelData.max + "°"; color: root.fg; font { family: root.font; pixelSize: 13; bold: true } }
                                    HoverHandler { id: dayHover }
                                    Rectangle {
                                        visible: dayHover.hovered
                                        x: 96; y: -height + 4; z: 10
                                        width: dayTip.implicitWidth + 18; height: 24; radius: 12
                                        color: root.bg
                                        border { width: 1; color: root.surface }
                                        Text { id: dayTip; anchors.centerIn: parent; text: modelData.desc; color: root.fg; font { family: root.font; pixelSize: 11 } }
                                    }
                                }
                            }
                        }
                    }
                    // ClippingRectangle (Quickshell.Widgets) : découpe la carte selon les coins arrondis, clip ne le fait pas
                    ClippingRectangle {
                        visible: !!root.weatherMap || weatherMapLoader.status === Loader.Error
                        width: root.weatherMapFull ? 1004 : 592
                        height: root.weatherMapFull ? 642 : 308
                        radius: 22
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                        Loader {
                            id: weatherMapLoader
                            anchors.fill: parent
                            source: "WeatherMap.qml"
                            asynchronous: true
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: weatherMapLoader.status === Loader.Error || !!root.weatherMap?.error
                            text: root.weatherMap?.error ?? "Carte indisponible (QtLocation manquant)"
                            color: root.dim
                            font { family: root.font; pixelSize: 13 }
                        }
                    }
                }
            }

            // ============ Onglet : Temps d'écran ============
            // Façon « Temps d'écran » d'Apple : jour (barres par heure empilées par catégorie),
            // semaine, applications, compteur à vie. Données : root.screen (screentime-fetch).
            Column {
                id: stTab
                visible: root.dashTab === "screen"
                width: 1004
                spacing: 12
                readonly property var t: root.screen?.today ?? null
                readonly property var life: root.screen?.lifetime ?? null
                readonly property var week: root.screen?.week ?? []
                onVisibleChanged: if (visible && !stProc.running) stProc.running = true
                function catsSorted(m) { return Object.keys(m ?? {}).sort((a, b) => m[b] - m[a]) }
                function dateFr(iso, fmt) { return iso ? Qt.locale("fr_FR").toString(new Date(iso + "T12:00:00"), fmt) : "" }

                Row {
                    spacing: 12

                    // ---- Aujourd'hui
                    DashCard {
                        width: 640; height: 300
                        Column {
                            anchors { fill: parent; margins: 20 }
                            spacing: 10
                            Row {
                                width: parent.width
                                Column {
                                    width: parent.width - stSide.width
                                    spacing: 2
                                    Text { text: "AUJOURD'HUI"; color: root.dim; font { family: root.font; pixelSize: 11; bold: true; letterSpacing: 1 } }
                                    Text {
                                        text: stTab.t ? root.stLong(stTab.t.total) : "…"
                                        color: root.fg
                                        font { family: root.font; pixelSize: 30; bold: true }
                                    }
                                    Text {
                                        visible: !!stTab.t && stTab.t.avg7 > 0
                                        readonly property int diff: stTab.t ? stTab.t.total - stTab.t.avg7 : 0
                                        text: (diff >= 0 ? "󰁝 " : "󰁅 ") + root.stLong(Math.abs(diff)) + (diff >= 0 ? " de plus" : " de moins") + " que la moyenne sur 7 jours"
                                        color: diff > 0 ? root.stColor("games") : root.stColor("dev")
                                        font { family: root.font; pixelSize: 12 }
                                    }
                                }
                                Column {
                                    id: stSide
                                    spacing: 4
                                    Repeater {
                                        model: stTab.t ? [["󰔟", "Première activité", stTab.t.first ?? "—"],
                                                          ["󰍽", "Reprises", String(stTab.t.pickups)],
                                                          ["󰃭", "Hier", root.stLong(stTab.t.yesterday)]] : []
                                        delegate: Row {
                                            required property var modelData
                                            anchors.right: parent.right
                                            spacing: 6
                                            Text { text: modelData[1]; color: root.dim; font { family: root.font; pixelSize: 11 } }
                                            Text { text: modelData[2]; color: root.fg; font { family: root.font; pixelSize: 11; bold: true } }
                                            Text { text: modelData[0]; color: root.accent; font { family: root.font; pixelSize: 12 } }
                                        }
                                    }
                                }
                            }

                            // Barres par heure (échelle 60 min, comme Apple)
                            Item {
                                id: hourChart
                                width: parent.width
                                height: 130
                                readonly property real plotW: width - 34
                                readonly property real plotH: height - 18
                                Repeater {
                                    model: [60, 30, 0]
                                    delegate: Item {
                                        required property int modelData
                                        y: hourChart.plotH * (1 - modelData / 60)
                                        width: hourChart.width; height: 1
                                        Rectangle { width: hourChart.plotW; height: 1; color: modelData ? root.surface : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18) }
                                        Text {
                                            x: hourChart.plotW + 6; anchors.verticalCenter: parent.verticalCenter
                                            text: modelData + " min"; color: root.dim
                                            font { family: root.font; pixelSize: 9 }
                                        }
                                    }
                                }
                                Repeater {
                                    model: 24
                                    delegate: Item {
                                        id: hb
                                        required property int index
                                        readonly property var h: stTab.t?.hours?.[index] ?? {}
                                        readonly property real tot: Object.values(h).reduce((a, b) => a + b, 0)
                                        readonly property real slot: hourChart.plotW / 24
                                        x: index * slot + 2
                                        width: slot - 4
                                        height: hourChart.plotH
                                        ClippingRectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: Math.min(1, hb.tot / 3600) * parent.height
                                            radius: 3
                                            color: "transparent"
                                            Column {
                                                anchors.bottom: parent.bottom
                                                width: parent.width
                                                Repeater {
                                                    // Empilement : première catégorie en haut
                                                    model: root.stOrder.filter(c => hb.h[c] > 0)
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        width: parent.width
                                                        height: Math.min(1, hb.tot / 3600) * hb.height * hb.h[modelData] / hb.tot
                                                        color: root.stColor(modelData)
                                                    }
                                                }
                                            }
                                        }
                                        Rectangle {
                                            visible: hb.index === dash.now.getHours()
                                            anchors { bottom: parent.bottom; bottomMargin: -5; horizontalCenter: parent.horizontalCenter }
                                            width: 4; height: 4; radius: 2; color: root.accent
                                        }
                                        Text {
                                            visible: hb.index % 6 === 0
                                            anchors { top: parent.bottom; topMargin: 6 }
                                            text: hb.index + " h"; color: root.dim
                                            font { family: root.font; pixelSize: 9 }
                                        }
                                    }
                                }
                            }

                            // Catégories du jour
                            Flow {
                                width: parent.width
                                spacing: 14
                                Repeater {
                                    model: stTab.catsSorted(stTab.t?.cats)
                                    delegate: Row {
                                        required property string modelData
                                        spacing: 6
                                        Rectangle { width: 9; height: 9; radius: 5; color: root.stColor(modelData); anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: root.stName(modelData); color: root.dim; font { family: root.font; pixelSize: 11 } }
                                        Text { text: root.stLong(stTab.t.cats[modelData]); color: root.fg; font { family: root.font; pixelSize: 11; bold: true } }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Semaine
                    DashCard {
                        width: 352; height: 300
                        Column {
                            anchors { fill: parent; margins: 20 }
                            spacing: 4
                            Text { text: "7 DERNIERS JOURS"; color: root.dim; font { family: root.font; pixelSize: 11; bold: true; letterSpacing: 1 } }
                            Text {
                                readonly property var days: stTab.week.filter(d => d.total > 0)
                                text: days.length ? "Moyenne " + root.stLong(days.reduce((a, d) => a + d.total, 0) / days.length) : "—"
                                color: root.fg
                                font { family: root.font; pixelSize: 18; bold: true }
                            }
                            Item {
                                id: weekChart
                                width: parent.width
                                height: 200
                                readonly property real plotH: height - 34
                                readonly property real maxS: Math.max(3600, ...stTab.week.map(d => d.total)) * 1.1
                                readonly property var nonZero: stTab.week.filter(d => d.total > 0)
                                readonly property real avg: nonZero.length ? nonZero.reduce((a, d) => a + d.total, 0) / nonZero.length : 0
                                Row {
                                    y: 12
                                    spacing: (weekChart.width - 7 * 30) / 6
                                    Repeater {
                                        model: stTab.week
                                        delegate: Item {
                                            id: wd
                                            required property var modelData
                                            required property int index
                                            readonly property bool isToday: index === 6
                                            width: 30; height: weekChart.plotH
                                            ClippingRectangle {
                                                anchors.bottom: parent.bottom
                                                width: parent.width
                                                height: wd.modelData.total / weekChart.maxS * parent.height
                                                radius: 6
                                                color: "transparent"
                                                opacity: wd.isToday ? 1 : 0.75
                                                Column {
                                                    anchors.bottom: parent.bottom
                                                    width: parent.width
                                                    Repeater {
                                                        model: root.stOrder.filter(c => wd.modelData.cats[c] > 0)
                                                        delegate: Rectangle {
                                                            required property string modelData
                                                            width: parent.width
                                                            height: wd.modelData.cats[modelData] / weekChart.maxS * wd.height
                                                            color: root.stColor(modelData)
                                                        }
                                                    }
                                                }
                                            }
                                            Text {
                                                anchors { top: parent.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                                                text: wd.modelData.label
                                                color: wd.isToday ? root.accent : root.dim
                                                font { family: root.font; pixelSize: 11; bold: wd.isToday }
                                            }
                                            MouseArea { id: wdMa; anchors.fill: parent; hoverEnabled: true }
                                            Rectangle {
                                                visible: wdMa.containsMouse
                                                anchors { bottom: parent.bottom; bottomMargin: Math.min(parent.height - 6, wd.modelData.total / weekChart.maxS * parent.height + 4); horizontalCenter: parent.horizontalCenter }
                                                width: wdTip.implicitWidth + 12; height: 20; radius: 6
                                                color: root.bg
                                                z: 5
                                                Text { id: wdTip; anchors.centerIn: parent; text: root.stLong(wd.modelData.total); color: root.fg; font { family: root.font; pixelSize: 10; bold: true } }
                                            }
                                        }
                                    }
                                }
                                // Moyenne (pointillés)
                                Row {
                                    visible: weekChart.avg > 0
                                    y: 12 + weekChart.plotH * (1 - weekChart.avg / weekChart.maxS)
                                    spacing: 4
                                    Repeater {
                                        model: Math.floor(weekChart.width / 8)
                                        delegate: Rectangle { width: 4; height: 1; color: root.stColor("dev") }
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    spacing: 12

                    // ---- Applications du jour
                    DashCard {
                        width: 496; height: 300
                        Column {
                            anchors { fill: parent; margins: 20 }
                            spacing: 10
                            Text { text: "APPLICATIONS LES PLUS UTILISÉES"; color: root.dim; font { family: root.font; pixelSize: 11; bold: true; letterSpacing: 1 } }
                            Text {
                                visible: !stTab.t || !Object.keys(stTab.t.apps).length
                                text: "Pas encore d'activité aujourd'hui"
                                color: root.dim
                                font { family: root.font; pixelSize: 12 }
                            }
                            Repeater {
                                model: stTab.t ? Object.keys(stTab.t.apps).slice(0, 6) : []
                                delegate: Row {
                                    id: ar
                                    required property string modelData
                                    readonly property var a: stTab.t.apps[modelData]
                                    readonly property real maxS: stTab.t.apps[Object.keys(stTab.t.apps)[0]].s
                                    width: parent.width
                                    height: 32
                                    spacing: 12
                                    Rectangle {
                                        width: 32; height: 32; radius: 9
                                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                                        IconImage {
                                            id: arIcon
                                            anchors.centerIn: parent
                                            implicitSize: 22
                                            source: ar.a.icon ? "file://" + ar.a.icon : root.stAppIcon(ar.a.id)
                                            visible: status === Image.Ready
                                        }
                                        Text {
                                            visible: !arIcon.visible
                                            anchors.centerIn: parent
                                            text: ar.modelData.charAt(0)
                                            color: root.stColor(ar.a.cat)
                                            font { family: root.font; pixelSize: 15; bold: true }
                                        }
                                    }
                                    Column {
                                        width: parent.width - 44 - 12 - 70
                                        spacing: 5
                                        anchors.verticalCenter: parent.verticalCenter
                                        Row {
                                            spacing: 8
                                            Text { text: ar.modelData; color: root.fg; font { family: root.font; pixelSize: 12; bold: true } }
                                            Text { text: root.stName(ar.a.cat); color: root.dim; anchors.bottom: parent.bottom; anchors.bottomMargin: 1; font { family: root.font; pixelSize: 10 } }
                                        }
                                        Rectangle {
                                            width: parent.width; height: 5; radius: 3
                                            color: root.surface
                                            Rectangle {
                                                width: Math.max(5, parent.width * ar.a.s / ar.maxS); height: 5; radius: 3
                                                color: root.stColor(ar.a.cat)
                                            }
                                        }
                                    }
                                    Text {
                                        width: 70
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: root.stLong(ar.a.s)
                                        color: root.fg
                                        font { family: root.font; pixelSize: 12 }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Compteur à vie
                    DashCard {
                        width: 496; height: 300
                        Column {
                            anchors { fill: parent; margins: 20 }
                            spacing: 12
                            Row {
                                width: parent.width
                                Column {
                                    width: parent.width - 120
                                    spacing: 2
                                    Text { text: "À VIE"; color: root.dim; font { family: root.font; pixelSize: 11; bold: true; letterSpacing: 1 } }
                                    Text {
                                        text: stTab.life ? root.stLong(stTab.life.total) : "…"
                                        color: root.accent
                                        font { family: root.font; pixelSize: 30; bold: true }
                                    }
                                    Text {
                                        text: stTab.life ? "depuis le " + stTab.dateFr(stTab.life.since, "d MMMM yyyy") + "  ·  " + stTab.life.days + " jour" + (stTab.life.days > 1 ? "s" : "") + " actif" + (stTab.life.days > 1 ? "s" : "") : ""
                                        color: root.dim
                                        font { family: root.font; pixelSize: 11 }
                                    }
                                }
                                Column {
                                    width: 120
                                    spacing: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text { anchors.right: parent.right; text: stTab.life ? (stTab.life.total / 86400).toLocaleString(Qt.locale("fr_FR"), "f", 1) : "—"; color: root.fg; font { family: root.font; pixelSize: 22; bold: true } }
                                    Text { anchors.right: parent.right; text: "jours d'écran"; color: root.dim; font { family: root.font; pixelSize: 10 } }
                                }
                            }
                            // Répartition à vie (barre horizontale empilée)
                            ClippingRectangle {
                                width: parent.width; height: 12; radius: 6
                                color: root.surface
                                Row {
                                    Repeater {
                                        model: stTab.life ? Object.keys(stTab.life.cats) : []
                                        delegate: Rectangle {
                                            required property string modelData
                                            width: stTab.life.total ? stTab.life.cats[modelData] / stTab.life.total * 456 : 0
                                            height: 12
                                            color: root.stColor(modelData)
                                        }
                                    }
                                }
                            }
                            Grid {
                                columns: 2
                                columnSpacing: 16
                                rowSpacing: 6
                                Repeater {
                                    model: stTab.life ? Object.keys(stTab.life.cats).slice(0, 6) : []
                                    delegate: Row {
                                        required property string modelData
                                        width: 220
                                        spacing: 6
                                        Rectangle { width: 9; height: 9; radius: 5; color: root.stColor(modelData); anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: root.stName(modelData); color: root.dim; width: 120; elide: Text.ElideRight; font { family: root.font; pixelSize: 11 } }
                                        Text { text: root.stLong(stTab.life.cats[modelData]); color: root.fg; font { family: root.font; pixelSize: 11; bold: true } }
                                    }
                                }
                            }
                            Row {
                                spacing: 10
                                Repeater {
                                    model: stTab.life ? [["Moyenne / jour", root.stLong(stTab.life.avg)],
                                                         ["Record", stTab.life.best ? root.stLong(stTab.life.best.total) : "—",
                                                          stTab.life.best ? stTab.dateFr(stTab.life.best.date, "d MMM") : ""],
                                                         ["Reprises", stTab.life.pickups.toLocaleString(Qt.locale("fr_FR"), "f", 0)],
                                                         ["Appli n° 1", Object.keys(stTab.life.apps)[0] ?? "—"]] : []
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 106; height: 58; radius: 14
                                        color: root.surface
                                        Column {
                                            anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                            spacing: 2
                                            Text { text: modelData[0]; color: root.dim; font { family: root.font; pixelSize: 10 } }
                                            Text { width: parent.width; elide: Text.ElideRight; text: modelData[1]; color: root.fg; font { family: root.font; pixelSize: 13; bold: true } }
                                            Text { visible: !!modelData[2]; text: modelData[2] ?? ""; color: root.dim; font { family: root.font; pixelSize: 9 } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ============ Onglet : Performances ============
            Item {
                visible: root.dashTab === "perf"
                width: 1004
                height: perf.implicitHeight
                Loader {
                    id: perf
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 1004
                    sourceComponent: perfPanel
                }
            }
        }
    }

    // ===================== Performances (façon Caelestia) =====================
    // Anneau de progression
    component Ring: Item {
        id: ring
        property real value: 0
        property real thickness: 6
        property color colour: root.accent
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.surface
                strokeWidth: ring.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: ring.width / 2 - ring.thickness / 2; radiusY: radiusX
                    startAngle: 0; sweepAngle: 360
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: ring.colour
                strokeWidth: ring.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: ring.width / 2 - ring.thickness / 2; radiusY: radiusX
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0.001, Math.min(1, ring.value))
                    Behavior on sweepAngle { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    // Carte « héros » : processeur ou carte graphique
    component HeroCard: DashCard {
        id: hero
        property string icon
        property string label
        property string subLabel
        property color tint: root.accent
        property real usage: 0          // 0..1
        property real temperature: 0    // °C
        property var cores: []          // utilisation par cœur logique, en % (vide = pas de barres)
        width: 496; height: 210
        // Forme selon la charge, comme Caelestia : cookie < 40 % < soleil < 80 % < explosion
        readonly property int band: usage >= 0.8 ? 2 : usage >= 0.4 ? 1 : 0

        Ring {
            id: heroRing
            x: 22; y: 22
            width: 64; height: 64
            value: hero.usage
            colour: hero.tint
            Text { anchors.centerIn: parent; text: hero.icon; color: hero.tint; font { family: root.font; pixelSize: 24 } }
        }
        Column {
            anchors { left: heroRing.right; leftMargin: 16; verticalCenter: heroRing.verticalCenter; right: shapeBox.left; rightMargin: 12 }
            spacing: 2
            Text { text: hero.label; color: hero.tint; font { family: root.font; pixelSize: 18; bold: true } }
            Text { width: parent.width; elide: Text.ElideRight; text: hero.subLabel; color: root.dim; font { family: root.font; pixelSize: 12 } }
        }
        // Une mini-barre par cœur logique, au-dessus de la température
        Row {
            id: coreBars
            visible: hero.cores.length > 0
            anchors { left: parent.left; leftMargin: 26; bottom: tempCol.top; bottomMargin: 14 }
            spacing: 4
            Repeater {
                model: hero.cores
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: (220 - (hero.cores.length - 1) * coreBars.spacing) / hero.cores.length
                    height: 40
                    radius: 3
                    color: root.surface
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: Math.max(2, parent.height * Math.min(1, parent.modelData / 100))
                        radius: 3
                        // Cœur saturé : couleur d'alerte
                        color: parent.modelData >= 90 ? (root.wal ? root.wal.colors.color1 : "red") : hero.tint
                        Behavior on height { NumberAnimation { duration: 400 } }
                    }
                    MouseArea { id: coreHover; anchors.fill: parent; hoverEnabled: true }
                    ToolTip.visible: coreHover.containsMouse
                    ToolTip.text: "Cœur " + index + " : " + modelData + " %"
                }
            }
        }
        // Température en bas à gauche
        Column {
            id: tempCol
            anchors { left: parent.left; leftMargin: 26; bottom: parent.bottom; bottomMargin: 26 }
            spacing: 6
            Row {
                spacing: 6
                Text {
                    text: hero.temperature > 85 ? "󰸁" : "󰔏"
                    color: hero.temperature > 85 ? (root.wal ? root.wal.colors.color1 : "red") : hero.tint
                    font { family: root.font; pixelSize: 18 }
                }
                Text { text: Math.round(hero.temperature) + " °C"; color: root.fg; font { family: root.font; pixelSize: 15; bold: true } }
            }
            Rectangle {
                width: 220; height: 6; radius: 3
                color: root.surface
                Rectangle {
                    width: parent.width * Math.min(1, hero.temperature / 100)
                    height: parent.height; radius: 3
                    color: hero.tint
                    Behavior on width { NumberAnimation { duration: 500 } }
                }
            }
        }
        // Utilisation dans la forme Material, en bas à droite
        Item {
            id: shapeBox
            anchors { right: parent.right; rightMargin: 22; bottom: parent.bottom; bottomMargin: 18 }
            width: 132; height: 150
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Utilisation"
                color: root.dim
                font { family: root.font; pixelSize: 11 }
            }
            SunnyShape {
                id: shape
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                width: 124; height: 124
                fill: Qt.rgba(hero.tint.r, hero.tint.g, hero.tint.b, 0.22)
                lobes: hero.band === 2 ? 12 : hero.band === 1 ? 8 : 4
                depth: hero.band === 2 ? 0.1 : hero.band === 1 ? 0.09 : 0.14
                Text {
                    anchors.centerIn: parent
                    text: Math.round(hero.usage * 100) + "%"
                    color: hero.tint
                    font { family: root.font; pixelSize: 26; bold: true }
                }
            }
        }
    }

    // Petite carte avec anneau central (stockage, mémoire)
    component RingCard: DashCard {
        id: rc
        property string icon
        property string title
        property real value: 0
        property string detail
        property string extra
        height: 250
        Row {
            anchors { left: parent.left; top: parent.top; margins: 20 }
            spacing: 8
            Text { text: rc.icon; color: root.accent; font { family: root.font; pixelSize: 17 } }
            Text { text: rc.title; color: root.fg; font { family: root.font; pixelSize: 15; bold: true } }
        }
        Ring {
            id: rcRing
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 56 }
            width: 116; height: 116
            thickness: 9
            value: rc.value
            Column {
                anchors.centerIn: parent
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(rc.value * 100) + "%"; color: root.accent; font { family: root.font; pixelSize: 22; bold: true } }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "utilisé"; color: root.dim; font { family: root.font; pixelSize: 11 } }
            }
        }
        Column {
            anchors { horizontalCenter: parent.horizontalCenter; top: rcRing.bottom; topMargin: 12 }
            spacing: 2
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: rc.detail; color: root.fg; font { family: root.font; pixelSize: 13; bold: true } }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: rc.extra; color: root.dim; font { family: root.font; pixelSize: 11 } }
        }
    }

    // Tokens Claude Code : 26296503 → « 26,3 M » ; coût API → « 10,88 $ »
    function tokStr(n) {
        return n >= 1e9 ? (n / 1e9).toFixed(2).replace(".", ",") + " Md"
             : n >= 1e6 ? (n / 1e6).toFixed(1).replace(".", ",") + " M"
             : n >= 1e3 ? Math.round(n / 1e3) + " k" : String(n)
    }
    function usdStr(c) { return c.toFixed(2).replace(".", ",") + " $" }
    function tokLine(t) { return t ? root.tokStr(t.tokens) + " tokens · ≈ " + root.usdStr(t.cost) + " en API" : "" }

    function bytes(b) {
        return b >= 1073741824 ? (b / 1073741824).toFixed(1) + " Go"
             : b >= 1048576 ? (b / 1048576).toFixed(1) + " Mo"
             : (b / 1024).toFixed(0) + " Ko"
    }

    Component {
        id: perfPanel
        Column {
            id: perf
            spacing: 12
            readonly property var s: root.stats

            Row {
                spacing: 12
                HeroCard {
                    icon: "󰻠"
                    label: "Processeur"
                    subLabel: perf.s ? perf.s.cpu.name + " · " + perf.s.cpu.freq + " GHz" : "…"
                    usage: perf.s ? perf.s.cpu.usage / 100 : 0
                    temperature: perf.s?.cpu.temp ?? 0
                    cores: perf.s?.cpu.perCore ?? []
                    tint: root.accent
                }
                HeroCard {
                    icon: "󰢮"
                    label: "Carte graphique"
                    subLabel: perf.s?.gpu ? perf.s.gpu.name + " · " + perf.s.gpu.power + " W" : "…"
                    usage: perf.s?.gpu ? perf.s.gpu.usage / 100 : 0
                    temperature: perf.s?.gpu?.temp ?? 0
                    tint: root.wal ? root.wal.colors.color5 : "#f5bde6"
                }
            }

            Row {
                spacing: 12

                RingCard {
                    width: 260
                    icon: "󰋊"; title: "Stockage"
                    value: perf.s ? perf.s.disk.used / perf.s.disk.total : 0
                    detail: perf.s ? perf.s.disk.used.toFixed(0) + " / " + perf.s.disk.total.toFixed(0) + " Go" : "…"
                    extra: perf.s ? "SSD : " + perf.s.disk.nvmeTemps.map(t => t + " °C").join(" · ") : ""
                }

                // Réseau : graphique du trafic
                DashCard {
                    width: 432; height: 250
                    Row {
                        anchors { left: parent.left; top: parent.top; margins: 20 }
                        spacing: 8
                        Text { text: "󰈀"; color: root.accent; font { family: root.font; pixelSize: 17 } }
                        Text { text: "Réseau"; color: root.fg; font { family: root.font; pixelSize: 15; bold: true } }
                    }
                    Canvas {
                        id: graph
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 52; margins: 20 }
                        height: 110
                        property var down: root.netDown
                        property var up: root.netUp
                        onDownChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const n = 60, max = Math.max(1024, ...down, ...up)
                            const draw = (data, colour, fillAlpha) => {
                                if (data.length < 2) return
                                ctx.beginPath()
                                data.forEach((v, i) => {
                                    const x = width * (n - data.length + i) / (n - 1)
                                    const y = height - height * v / max
                                    i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)
                                })
                                ctx.strokeStyle = colour
                                ctx.lineWidth = 2
                                ctx.stroke()
                                ctx.lineTo(width, height)
                                ctx.lineTo(width * (n - data.length) / (n - 1), height)
                                ctx.closePath()
                                ctx.fillStyle = Qt.rgba(colour.r, colour.g, colour.b, fillAlpha)
                                ctx.fill()
                            }
                            draw(down, root.accent, 0.25)
                            draw(up, root.wal ? Qt.color(root.wal.colors.color5) : Qt.color("#f5bde6"), 0.15)
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.netDown.length < 2
                            text: "Collecte des données…"
                            color: root.dim
                            font { family: root.font; pixelSize: 12 }
                        }
                    }
                    Row {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
                        spacing: 24
                        Column {
                            Text { text: "󰇚 Réception"; color: root.accent; font { family: root.font; pixelSize: 11 } }
                            Text { text: perf.s ? root.rate(perf.s.net.down) : "…"; color: root.fg; font { family: root.font; pixelSize: 14; bold: true } }
                        }
                        Column {
                            Text { text: "󰕒 Envoi"; color: root.wal ? root.wal.colors.color5 : "#f5bde6"; font { family: root.font; pixelSize: 11 } }
                            Text { text: perf.s ? root.rate(perf.s.net.up) : "…"; color: root.fg; font { family: root.font; pixelSize: 14; bold: true } }
                        }
                        Column {
                            Text { text: "󰄉 Depuis le démarrage"; color: root.dim; font { family: root.font; pixelSize: 11 } }
                            Text { text: perf.s ? "↓ " + root.bytes(perf.s.net.totalDown) + "  ↑ " + root.bytes(perf.s.net.totalUp) : "…"; color: root.fg; font { family: root.font; pixelSize: 14; bold: true } }
                        }
                    }
                }

                RingCard {
                    width: 288
                    icon: "󰍛"; title: "Mémoire"
                    value: perf.s ? perf.s.mem.used / perf.s.mem.total : 0
                    detail: perf.s ? root.gb(perf.s.mem.used) + " / " + root.gb(perf.s.mem.total) : "…"
                    extra: perf.s ? "Swap " + root.gb(perf.s.mem.swapUsed) + " · VRAM " + (perf.s.gpu ? root.gb(perf.s.gpu.vramUsed) : "—") : ""
                }
            }

            // Claude Code + bouton Ressources
            Row {
                spacing: 12
                DashCard {
                    visible: !!perf.s?.claude
                    width: 680; height: 64
                    Row {
                        anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                        spacing: 24
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "󰚩  Claude Code"; color: "#D97757"; font { family: root.font; pixelSize: 15; bold: true } }
                        Repeater {
                            model: [["Session (5 h)", perf.s?.claude?.five_hour ?? 0, perf.s?.claude?.tokens?.session],
                                    ["Semaine", perf.s?.claude?.seven_day ?? 0, perf.s?.claude?.tokens?.week]]
                            delegate: Column {
                                required property var modelData
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                Row {
                                    spacing: 10
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: root.dim; font { family: root.font; pixelSize: 12 } }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 120; height: 6; radius: 3; color: root.surface
                                        Rectangle { width: parent.width * modelData[1] / 100; height: parent.height; radius: 3; color: "#D97757" }
                                    }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1] + " %"; color: root.fg; font { family: root.font; pixelSize: 13; bold: true } }
                                }
                                // Tokens consommés et leur prix au tarif de l'API
                                Text {
                                    visible: !!modelData[2]
                                    text: root.tokLine(modelData[2])
                                    color: root.dim
                                    font { family: root.font; pixelSize: 11 }
                                }
                            }
                        }
                    }
                }
                DashCard {
                    width: perf.s?.claude ? 312 : 1004; height: 64
                    color: resMa.containsMouse ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                    Text {
                        anchors.centerIn: parent
                        text: "󰄨   Ouvrir Ressources"
                        color: resMa.containsMouse ? root.bg : root.fg
                        font { family: root.font; pixelSize: 14; bold: true }
                    }
                    MouseArea {
                        id: resMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { root.panel = ""; Quickshell.execDetached(["resources"]) }
                    }
                }
            }
        }
    }

    // ===================== Vitals =====================
    property var stats: null
    property var netDown: []
    property var netUp: []
    Process {
        id: statsProc
        command: [root.home + "/.local/bin/sysstats"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.stats = JSON.parse(text) } catch (e) { return }
                // Historique réseau pour le graphique (60 points = 2 min)
                root.netDown = root.netDown.concat([root.stats.net.down]).slice(-60)
                root.netUp = root.netUp.concat([root.stats.net.up]).slice(-60)
            }
        }
    }
    // Rafraîchi toutes les 2 s, seulement quand le menu est ouvert.
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.panel === "vitals" || root.panel === "dashboard"
        onTriggered: if (!statsProc.running) statsProc.running = true
    }
    function rate(b) {
        return b >= 1048576 ? (b / 1048576).toFixed(1) + " Mo/s" : (b / 1024).toFixed(0) + " Ko/s"
    }
    function gb(v) { return v.toFixed(1) + " Go" }

    component StatRow: Item {
        id: row
        property string icon
        property string name
        property string value
        property real ratio: -1      // -1 = pas de barre
        property bool hot: false
        width: parent.width
        height: ratio >= 0 ? 36 : 22
        Text {
            id: ic
            width: 26
            text: row.icon
            color: row.hot ? (root.wal ? root.wal.colors.color1 : "red") : root.accent
            font { family: root.font; pixelSize: 15 }
        }
        Text {
            anchors.left: ic.right
            text: row.name
            color: root.dim
            font { family: root.font; pixelSize: 13 }
        }
        Text {
            anchors.right: parent.right
            text: row.value
            color: row.hot ? (root.wal ? root.wal.colors.color1 : "red") : root.fg
            font { family: root.font; pixelSize: 13; bold: true }
        }
        Rectangle {
            visible: row.ratio >= 0
            anchors { left: ic.right; right: parent.right; bottom: parent.bottom; bottomMargin: 4 }
            height: 5; radius: 3
            color: root.surface
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, row.ratio))
                height: parent.height; radius: 3
                color: row.hot ? (root.wal ? root.wal.colors.color1 : "red") : root.accent
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }
    }

    Component {
        id: vitalsPanel
        Column {
            spacing: 8
            readonly property var s: root.stats

            Title { text: "󰻠  Processeur" }
            StatRow { icon: "󰓅"; name: "Utilisation"; value: s ? s.cpu.usage + " %" : "…"; ratio: s ? s.cpu.usage / 100 : 0 }
            StatRow { icon: "󰔏"; name: "Température"; value: s?.cpu.temp != null ? s.cpu.temp + " °C" : "—"; hot: (s?.cpu.temp ?? 0) >= 85 }
            StatRow { icon: "󰾆"; name: "Fréquence moyenne"; value: s?.cpu.freq ? s.cpu.freq + " GHz" : "—" }
            StatRow { icon: "󰑮"; name: "Charge (1 / 5 / 15 min)"; value: s ? s.cpu.load.join("  ") : "…" }

            Rectangle { width: parent.width; height: 1; color: root.surface }
            Title { text: "󰢮  Carte graphique" + (s?.gpu ? " · " + s.gpu.name : "") }
            StatRow { icon: "󰓅"; name: "Utilisation"; value: s?.gpu ? s.gpu.usage + " %" : "—"; ratio: s?.gpu ? s.gpu.usage / 100 : 0 }
            StatRow { icon: "󰍛"; name: "Mémoire vidéo"; value: s?.gpu ? root.gb(s.gpu.vramUsed) + " / " + root.gb(s.gpu.vramTotal) : "—"; ratio: s?.gpu ? s.gpu.vramUsed / s.gpu.vramTotal : 0 }
            StatRow { icon: "󰔏"; name: "Température · ventilateur"; value: s?.gpu ? s.gpu.temp + " °C · " + (s.gpu.fan ?? "—") + " %" : "—"; hot: (s?.gpu?.temp ?? 0) >= 85 }
            StatRow { icon: "󱐋"; name: "Consommation"; value: s?.gpu ? s.gpu.power + " W" : "—" }

            Rectangle { width: parent.width; height: 1; color: root.surface }
            Title { text: "󰋊  Mémoire et stockage" }
            StatRow { icon: "󰍛"; name: "RAM"; value: s ? root.gb(s.mem.used) + " / " + root.gb(s.mem.total) : "…"; ratio: s ? s.mem.used / s.mem.total : 0 }
            StatRow { icon: "󰓡"; name: "Swap"; value: s ? root.gb(s.mem.swapUsed) + " / " + root.gb(s.mem.swapTotal) : "…" }
            StatRow { icon: "󰋊"; name: "Disque /"; value: s ? s.disk.used.toFixed(0) + " / " + s.disk.total.toFixed(0) + " Go" : "…"; ratio: s ? s.disk.used / s.disk.total : 0 }
            StatRow { icon: "󰔏"; name: "SSD NVMe"; value: s ? s.disk.nvmeTemps.map(t => t + " °C").join(" · ") : "…" }

            Rectangle { width: parent.width; height: 1; color: root.surface }
            Title { text: "󰈀  Réseau" }
            StatRow { icon: "󰇚"; name: "Réception"; value: s ? root.rate(s.net.down) : "…" }
            StatRow { icon: "󰕒"; name: "Envoi"; value: s ? root.rate(s.net.up) : "…" }

            Rectangle { width: parent.width; height: 1; color: root.surface; visible: !!s?.claude }
            Title { text: "󰚩  Claude Code"; visible: !!s?.claude }
            StatRow { visible: s?.claude?.five_hour != null; icon: "󰔟"; name: "Session (5 h)"; value: (s?.claude?.five_hour ?? 0) + " %"; ratio: (s?.claude?.five_hour ?? 0) / 100 }
            StatRow { visible: s?.claude?.seven_day != null; icon: "󰃭"; name: "Semaine"; value: (s?.claude?.seven_day ?? 0) + " %"; ratio: (s?.claude?.seven_day ?? 0) / 100 }
            StatRow { visible: !!s?.claude?.tokens; icon: "󰆼"; name: "Tokens session · semaine"; value: s?.claude?.tokens ? root.tokStr(s.claude.tokens.session.tokens) + " · " + root.tokStr(s.claude.tokens.week.tokens) : "" }
            StatRow { visible: !!s?.claude?.tokens; icon: "󰇁"; name: "Équivalent API"; value: s?.claude?.tokens ? root.usdStr(s.claude.tokens.session.cost) + " · " + root.usdStr(s.claude.tokens.week.cost) : "" }

            // Bouton vers le gestionnaire de ressources
            Rectangle {
                width: parent.width
                height: 40
                radius: 10
                color: openHover.containsMouse ? root.accent : root.surface
                Text {
                    anchors.centerIn: parent
                    text: "󰄨   Ouvrir Ressources"
                    color: openHover.containsMouse ? root.bg : root.fg
                    font { family: root.font; pixelSize: 14; bold: true }
                }
                MouseArea {
                    id: openHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { root.panel = ""; Quickshell.execDetached(["resources"]) }
                }
            }
        }
    }

    // ===================== Alimentation =====================
    // jetbrainsd ignore SIGTERM et bloquait l'arrêt de session-2.scope : on le ferme avant.
    function stopJetbrainsd(cmd) {
        return ["sh", "-c", "pkill -x jetbrainsd; sleep 1; pkill -KILL -x jetbrainsd; " + cmd]
    }

    // Déconnexion, redémarrage et arrêt demandent une confirmation.
    Component {
        id: powerPanel
        Item {
            id: power
            readonly property var actions: [
                ["󰌾", "Verrouiller", ["hyprlock"], ""],
                ["󰍃", "Se déconnecter", ["hyprctl", "dispatch", "exit"], "Fermer la session ?"],
                ["󰜉", "Redémarrer", root.stopJetbrainsd("systemctl reboot"), "Redémarrer l'ordinateur ?"],
                ["󰐥", "Éteindre", root.stopJetbrainsd("systemctl poweroff"), "Éteindre l'ordinateur ?"]
            ]
            readonly property color danger: root.wal ? root.wal.colors.color1 : "#ed8796"
            property var pending: null
            implicitWidth: 348
            implicitHeight: pending ? confirm.implicitHeight : list.implicitHeight

            function run(a) {
                root.panel = ""
                Quickshell.execDetached(a[2])
            }

            Column {
                id: list
                visible: !power.pending
                spacing: 4
                Repeater {
                    model: power.actions
                    delegate: Rectangle {
                        required property var modelData
                        width: 348
                        height: 42
                        radius: 10
                        color: hov.containsMouse ? root.surface : "transparent"
                        Text {
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            text: parent.modelData[0] + "   " + parent.modelData[1]
                            color: root.fg
                            font { family: root.font; pixelSize: 14 }
                        }
                        MouseArea {
                            id: hov
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (parent.modelData[3]) power.pending = parent.modelData
                                else power.run(parent.modelData)
                            }
                        }
                    }
                }
            }

            Column {
                id: confirm
                visible: !!power.pending
                width: 348
                spacing: 14
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: power.pending ? power.pending[0] : ""
                    color: power.danger
                    font { family: root.font; pixelSize: 34 }
                }
                Title {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: power.pending ? power.pending[3] : ""
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Les applications ouvertes seront fermées."
                    color: root.dim
                    font { family: root.font; pixelSize: 12 }
                }
                Row {
                    spacing: 8
                    Rectangle {
                        width: 170; height: 40; radius: 10
                        color: cancelHov.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16) : root.surface
                        Text {
                            anchors.centerIn: parent
                            text: "Annuler"
                            color: root.fg
                            font { family: root.font; pixelSize: 14; bold: true }
                        }
                        MouseArea {
                            id: cancelHov
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: power.pending = null
                        }
                    }
                    Rectangle {
                        width: 170; height: 40; radius: 10
                        color: okHov.containsMouse ? power.danger : Qt.rgba(power.danger.r, power.danger.g, power.danger.b, 0.25)
                        Text {
                            anchors.centerIn: parent
                            text: power.pending ? power.pending[1] : ""
                            color: okHov.containsMouse ? root.bg : power.danger
                            font { family: root.font; pixelSize: 14; bold: true }
                        }
                        MouseArea {
                            id: okHov
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: power.run(power.pending)
                        }
                    }
                }
            }
        }
    }
}
