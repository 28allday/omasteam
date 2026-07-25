// omasteam-nightlight — Omarchy-quattro-style night light panel, in pure QML.
//
// Opened from the system menu's "Display & Monitor > Night Light" leaf, in place
// of kcmshell6 kcm_nightlight. Same card shape and QML-front / bash-back split
// as the bar's panels: taps go to the `nl_outbox` SQLite table and the launcher
// (omasteam-nightlight) writes kwinrc and keeps nl-state.json fresh.
//
// Dragging the temperature slider previews live through KWin's preview() call,
// so you pick a warmth by looking at the screen rather than at a number.
import QtQuick
import QtQuick.Window
import QtQuick.LocalStorage
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"
    width: 460
    height: 190

    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.margins.top: 8
    LayerShell.Window.margins.right: 12
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive

    // ---- theme palette (read from the bar daemon's state.json, like the bar) --
    property var st: ({})
    readonly property color cBg: st.colors ? st.colors.bg : "#1a1b26"
    readonly property color cFg: st.colors ? st.colors.fg : "#c0caf5"
    readonly property color cAccent: st.colors ? st.colors.accent : "#7aa2f7"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property string statePath: { var p = "@@STATE@@"; return p.charAt(0) === "/" ? p : "" }
    readonly property string nlStatePath: { var p = "@@NLSTATE@@"; return p.charAt(0) === "/" ? p : "" }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function g(cp) { return String.fromCodePoint(cp) }
    readonly property string icoMoon: g(0xF186)   // fa-moon
    readonly property string icoSun:  g(0xF185)   // fa-sun

    // Warm-to-neutral swatch for the slider fill, so the control looks like what
    // it does: 1000K is deep amber, 6500K is daylight.
    function tempColor(k) {
        var t = Math.max(0, Math.min(1, (k - 1000) / 5500))
        return Qt.rgba(1.0, 0.55 + 0.45 * t, 0.25 + 0.75 * t, 1.0)
    }

    property string _lastPal: ""
    function pollPalette() {
        if (!statePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastPal) return
                win._lastPal = xhr.responseText
                try { win.st = JSON.parse(xhr.responseText) } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + statePath)
        xhr.send()
    }

    // ---- night light state (nl-state.json, kept fresh by the launcher) -------
    property var nl: ({ available: true, enabled: false, mode: "automatic",
                        current: 6500, target: 6500, night: 4500, day: 6500 })
    property string _lastNl: ""
    function pollNl() {
        if (!nlStatePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastNl) return
                win._lastNl = xhr.responseText
                try {
                    var n = JSON.parse(xhr.responseText)
                    if (n && n.mode !== undefined) {
                        // Defensive fill, like the other panels.
                        win.nl = {
                            available: n.available !== false,
                            enabled: n.enabled === true,
                            mode: n.mode || "automatic",
                            current: n.current || 6500,
                            target: n.target || 6500,
                            night: n.night || 4500,
                            day: n.day || 6500
                        }
                        if (!win.dragging) win.tempShown = win.nl.night
                    }
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + nlStatePath)
        xhr.send()
    }
    Component.onCompleted: { pollPalette(); pollNl() }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: { win.pollNl(); win.pollPalette() } }

    readonly property var modes: [
        { id: "constant",  label: "Always" },
        { id: "automatic", label: "Sunset" },
        { id: "times",     label: "Times" }
    ]

    property int tempShown: 4500
    property bool dragging: false

    function dismiss() { win.visible = false; quitTimer.start() }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    // ---- command outbox (SQLite polled live by the launcher) -----------------
    function sendCmd(cmd) {
        try {
            var db = LocalStorage.openDatabaseSync("omasteam_nightlight", "1.0", "omasteam nightlight outbox", 100000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS nl_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO nl_outbox(cmd) VALUES(?)", [cmd])
            })
        } catch (e) { console.log("sendCmd failed:", e) }
    }

    // Snap to 100K: the difference between 4200K and 4237K is not a thing a
    // person can see, and round numbers make the readout legible.
    function setTemp(k) {
        tempShown = Math.max(1000, Math.min(6500, Math.round(k / 100) * 100))
        previewThrottle.restart()
    }
    Timer { id: previewThrottle; interval: 120; onTriggered: win.sendCmd("preview:" + win.tempShown) }
    function commitTemp() {
        sendCmd("temp:" + tempShown)
        sendCmd("preview-stop")
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 14
        color: win.cBg
        border.color: win.alpha(win.cFg, 0.12)
        border.width: 1
        MouseArea { anchors.fill: parent }

        Item {
            id: keys
            focus: true
            Keys.onPressed: function(e) {
                switch (e.key) {
                case Qt.Key_T:      win.sendCmd("toggle"); e.accepted = true; break
                case Qt.Key_Left:   win.setTemp(win.tempShown - 100); win.commitTemp(); e.accepted = true; break
                case Qt.Key_Right:  win.setTemp(win.tempShown + 100); win.commitTemp(); e.accepted = true; break
                case Qt.Key_Escape: win.dismiss(); e.accepted = true; break
                }
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ---- hero: state + toggle ----------------------------------------
            Item {
                width: parent.width
                height: 44

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: togglePill.left
                    anchors.rightMargin: 10
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.nl.enabled ? win.icoMoon : win.icoSun
                        color: win.nl.enabled ? win.tempColor(win.nl.current) : win.alpha(win.cFg, 0.45)
                        font { family: win.fontFamily; pixelSize: 22 }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 22 - parent.spacing
                        spacing: 2
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: "Night Light"
                            color: win.cFg
                            font { family: win.fontFamily; pixelSize: 14; bold: true }
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: {
                                if (!win.nl.available) return "NOT AVAILABLE ON THIS COMPOSITOR"
                                if (!win.nl.enabled) return "OFF"
                                // `current` is mid-transition warmth, which is
                                // the honest thing to show while it ramps.
                                return ("on · " + win.nl.current + "K · " + win.nl.mode).toUpperCase()
                            }
                            color: win.alpha(win.cFg, 0.55)
                            font { family: win.fontFamily; pixelSize: 11; letterSpacing: 1.1 }
                        }
                    }
                }

                Rectangle {
                    id: togglePill
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 22
                    radius: 11
                    enabled: win.nl.available
                    opacity: win.nl.available ? 1 : 0.4
                    color: win.nl.enabled ? win.cAccent : win.alpha(win.cFg, 0.2)
                    Rectangle {
                        width: 16; height: 16
                        radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: win.nl.enabled ? parent.width - width - 3 : 3
                        color: win.cBg
                        Behavior on x { NumberAnimation { duration: 120 } }
                    }
                    TapHandler { onTapped: if (win.nl.available) win.sendCmd("toggle") }
                }
            }

            // ---- schedule ----------------------------------------------------
            Column {
                width: parent.width
                spacing: 4

                SectionHeader { text: "SCHEDULE" }

                Row {
                    width: parent.width
                    height: 30
                    spacing: 6
                    Repeater {
                        model: win.modes
                        Pill {
                            required property var modelData
                            label: modelData.label
                            active: win.nl.mode === modelData.id
                            onTapped: win.sendCmd("mode:" + modelData.id)
                        }
                    }
                    // "Location" (manual coordinates) and per-day times need real
                    // input UI; KDE's own module stays in the menu for those.
                    Pill {
                        label: "Location"
                        active: win.nl.mode === "location"
                        dim: true
                        onTapped: win.sendCmd("mode:location")
                    }
                }
            }

            // ---- night temperature -------------------------------------------
            Column {
                width: parent.width
                spacing: 4

                SectionHeader { text: "NIGHT TEMPERATURE" }

                Item {
                    width: parent.width
                    height: 40

                    Text {
                        id: warmGlyph
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.icoMoon
                        color: win.tempColor(win.tempShown)
                        font { family: win.fontFamily; pixelSize: 16 }
                    }

                    Item {
                        id: track
                        anchors.left: warmGlyph.right
                        anchors.leftMargin: 12
                        anchors.right: kelvin.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height

                        readonly property real frac: (win.tempShown - 1000) / 5500

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 6; radius: 3
                            color: win.alpha(win.cFg, 0.15)
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * track.frac
                            height: 6; radius: 3
                            color: win.tempColor(win.tempShown)
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width * track.frac - width / 2
                            width: 16; height: 16; radius: 8
                            color: win.dragging ? win.tempColor(win.tempShown) : win.cFg
                            border.color: win.cBg
                            border.width: 2
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: function(m) {
                                win.dragging = true
                                win.setTemp(1000 + (m.x / track.width) * 5500)
                            }
                            onPositionChanged: function(m) {
                                if (win.dragging) win.setTemp(1000 + (m.x / track.width) * 5500)
                            }
                            onReleased: {
                                win.dragging = false
                                win.commitTemp()
                            }
                        }
                    }

                    Text {
                        id: kelvin
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 62
                        horizontalAlignment: Text.AlignRight
                        text: win.tempShown + "K"
                        color: win.cFg
                        font { family: win.fontFamily; pixelSize: 13 }
                    }
                }
            }
        }
    }

    // ---- shared bits ---------------------------------------------------------
    component SectionHeader: Text {
        color: win.alpha(win.cFg, 0.45)
        font { family: win.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.4 }
    }

    component Pill: Rectangle {
        id: pill
        property string label: ""
        property bool active: false
        property bool dim: false
        signal tapped()

        height: 28
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: pillText.implicitWidth + 22
        radius: 8
        color: active ? win.cAccent : (ph.hovered ? win.alpha(win.cFg, 0.12) : win.alpha(win.cFg, 0.06))
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.active ? win.cBg : win.alpha(win.cFg, pill.dim ? 0.45 : 0.85)
            font { family: win.fontFamily; pixelSize: 12; bold: pill.active }
        }

        HoverHandler { id: ph }
        TapHandler { onTapped: pill.tapped() }
    }
}
