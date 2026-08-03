// omasteam-steam — Steam launcher panel, in pure QML.
//
// Opened from the bar's Steam chip; anchored top-right under it (same
// layer-shell recipe as the volume/network/power panels: Top|Right + margins,
// static size).
//
// The chip used to switch straight to Game Mode with no way back to the DESKTOP
// Steam client except the ~/Desktop icons. This panel offers both, and is what
// those two icons (Return.desktop, steam.desktop) were removed in favour of.
//
// Game Mode is ARMED on the first tap and only fires on the second — it tears
// down the desktop session, and this is a touch surface an errant thumb can hit.
// Launching the desktop client is recoverable, so it fires immediately.
//
// Same split as the other panels: actions go to the `steam_outbox` SQLite table
// and the launcher (omasteam-steam) polls it live and runs the verb.
import QtQuick
import QtQuick.Window
import QtQuick.LocalStorage
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"
    width: 400
    height: 180

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
    readonly property color cDanger: "#f7768e"
    readonly property color cOk: "#9ece6a"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property string statePath: { var p = "@@STATE@@"; return p.charAt(0) === "/" ? p : "" }
    readonly property string stStatePath: { var p = "@@STSTATE@@"; return p.charAt(0) === "/" ? p : "" }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function g(cp) { return String.fromCodePoint(cp) }
    readonly property string icoSteam:   g(0xF1B6)   // fa-steam — hero, same as the bar chip
    readonly property string icoGamepad: g(0xF11B)   // fa-gamepad
    readonly property string icoDesktop: g(0xF108)   // fa-desktop

    // ---- bar palette ----------------------------------------------------------
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

    // ---- steam state (steam-state.json, refreshed by the launcher) ------------
    // sys = { gaming, running }
    property var sys: ({ gaming: false, running: false })
    property string _lastSys: ""
    function pollSys() {
        if (!stStatePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastSys) return
                win._lastSys = xhr.responseText
                try {
                    var s = JSON.parse(xhr.responseText)
                    if (s && s.gaming !== undefined) win.sys = s
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + stStatePath)
        xhr.send()
    }
    // Both polls in ONE onCompleted: two Component.onCompleted handlers on the
    // same object is "Property value set multiple times" — a silent death.
    Component.onCompleted: { pollPalette(); pollSys() }
    Timer { interval: 2000; repeat: true; running: true; onTriggered: { win.pollPalette(); win.pollSys() } }

    // ---- actions --------------------------------------------------------------
    // arm: true = ends the desktop session, needs a second tap to fire.
    readonly property var actions: [
        { cmd: "gaming",  glyph: icoGamepad, label: "Game Mode",       hint: "G", arm: true  },
        { cmd: "desktop", glyph: icoDesktop, label: "Steam (Desktop)", hint: "D", arm: false }
    ]

    property int selectedIndex: 0
    property string armed: ""        // cmd waiting for its confirming second tap
    Timer { id: disarm; interval: 4000; onTriggered: win.armed = "" }

    function dismiss() { win.visible = false; quitTimer.start() }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    // ---- command outbox (SQLite polled live by the launcher) -----------------
    function sendCmd(cmd) {
        try {
            var db = LocalStorage.openDatabaseSync("omasteam_steam", "1.0", "omasteam steam outbox", 100000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS steam_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO steam_outbox(cmd) VALUES(?)", [cmd])
            })
        } catch (e) { console.log("sendCmd failed:", e) }
    }

    function activate(row) {
        if (!row) return
        if (row.arm && win.armed !== row.cmd) {
            win.armed = row.cmd
            disarm.restart()
            return
        }
        win.armed = ""
        disarm.stop()
        // Unmap first, then let the launcher run the verb — the same
        // separate-event-cycle rule the other panels follow.
        win.sendCmd(row.cmd)
        win.dismiss()
    }
    function activateByKey(k) {
        for (var i = 0; i < actions.length; i++) {
            if (actions[i].hint === k) { win.selectedIndex = i; win.activate(actions[i]); return true }
        }
        return false
    }
    function moveSel(d) {
        var n = actions.length
        win.armed = ""
        win.selectedIndex = (win.selectedIndex + d + n) % n
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
                case Qt.Key_Down:
                case Qt.Key_Tab:    win.moveSel(1);  e.accepted = true; break
                case Qt.Key_Up:     win.moveSel(-1); e.accepted = true; break
                case Qt.Key_Return:
                case Qt.Key_Enter:  win.activate(win.actions[win.selectedIndex]); e.accepted = true; break
                case Qt.Key_Escape: win.dismiss(); e.accepted = true; break
                default:
                    if (e.text && win.activateByKey(e.text.toUpperCase())) e.accepted = true
                    break
                }
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ---- hero: Steam + what Game Mode will actually do ----------------
            Item {
                width: parent.width
                height: 44

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: heroTag.left
                    anchors.rightMargin: 10
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.icoSteam
                        color: win.cAccent
                        font { family: win.fontFamily; pixelSize: 22 }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Steam"
                            color: win.cFg
                            font { family: win.fontFamily; pixelSize: 14; bold: true }
                        }
                        Text {
                            // Game Mode is a straight switch only on a Deck that
                            // logs into desktop by default; otherwise it is a
                            // logout. Say which, rather than let it surprise.
                            text: (win.sys.gaming ? "SWITCHES TO GAME MODE" : "LOGS OUT TO GAME MODE")
                            color: win.alpha(win.cFg, 0.55)
                            font { family: win.fontFamily; pixelSize: 11; letterSpacing: 1.1 }
                        }
                    }
                }

                Text {
                    id: heroTag
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: win.sys.running === true
                    text: "RUNNING"
                    color: win.cOk
                    font { family: win.fontFamily; pixelSize: 10; letterSpacing: 1.1; bold: true }
                }
            }

            // ---- destinations --------------------------------------------------
            Column {
                width: parent.width
                spacing: 0

                Repeater {
                    model: win.actions

                    Rectangle {
                        required property int index
                        required property var modelData
                        width: parent.width
                        height: 44
                        radius: 9
                        readonly property bool sel: index === win.selectedIndex
                        readonly property bool isArmed: win.armed === modelData.cmd
                        color: isArmed ? win.cDanger
                             : sel ? win.cAccent
                             : (rowHover.hovered ? win.alpha(win.cFg, 0.08) : "transparent")

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                text: modelData.glyph
                                color: (isArmed || sel) ? win.cBg : win.cFg
                                font { family: win.fontFamily; pixelSize: 16 }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 22 - 60 - 24
                                text: isArmed ? "Tap again to confirm" : modelData.label
                                elide: Text.ElideRight
                                color: (isArmed || sel) ? win.cBg : win.cFg
                                font { family: win.fontFamily; pixelSize: 13; bold: isArmed }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 60
                                horizontalAlignment: Text.AlignRight
                                text: modelData.hint
                                color: (isArmed || sel) ? win.alpha(win.cBg, 0.7) : win.alpha(win.cFg, 0.4)
                                font { family: win.fontFamily; pixelSize: 11 }
                            }
                        }

                        HoverHandler { id: rowHover }
                        TapHandler {
                            onTapped: { win.selectedIndex = index; win.activate(modelData) }
                        }
                    }
                }
            }
        }
    }
}
