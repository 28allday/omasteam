// omasteam-power — Omarchy-quattro-style power/session panel, in pure QML.
//
// Opened from the bar's power chip; anchored top-right under it (same
// layer-shell recipe as the volume/network/bluetooth panels: Top|Right +
// margins, static size).
//
// Replaces KDE's stock LogoutPrompt. Hero shows the host + uptime (and the
// battery, on hardware that has one — read straight out of the bar daemon's
// state.json); below it the session actions.
//
// Anything that ends the session (log out / restart / shut down / return to
// gaming) is ARMED on the first tap and only fires on the second — this is a
// touch surface an errant thumb can hit. Lock and suspend are recoverable, so
// they fire immediately.
//
// Same split as the other panels: actions go to the `power_outbox` SQLite
// table and the launcher (omasteam-power) polls it live and runs the verb.
import QtQuick
import QtQuick.Window
import QtQuick.LocalStorage
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"
    width: 460
    height: 340

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
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property string statePath: { var p = "@@STATE@@"; return p.charAt(0) === "/" ? p : "" }
    readonly property string sysStatePath: { var p = "@@SYSSTATE@@"; return p.charAt(0) === "/" ? p : "" }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function g(cp) { return String.fromCodePoint(cp) }
    readonly property string icoPower:  g(0xF011)   // fa-power-off — hero
    readonly property string icoLock:   g(0xF023)   // fa-lock
    readonly property string icoSleep:  g(0xF0904)  // md-power-sleep
    readonly property string icoLogout: g(0xF0343)  // md-logout
    readonly property string icoReboot: g(0xF0709)  // md-restart
    readonly property string icoOff:    g(0xF0425)  // md-power
    readonly property string icoGaming: g(0xF1B6)   // fa-steam — same as the bar
    readonly property string icoBolt:   g(0xF0E7)   // fa-bolt

    function batIcon(pct) {
        if (pct >= 88) return g(0xF240)
        if (pct >= 63) return g(0xF241)
        if (pct >= 38) return g(0xF242)
        if (pct >= 13) return g(0xF243)
        return g(0xF244)
    }

    // ---- bar palette / battery ------------------------------------------------
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

    // ---- system state (power-state.json, refreshed by the launcher) -----------
    // sys = { host, user, uptime, kernel, gaming }
    property var sys: ({ host: "", user: "", uptime: "", kernel: "", gaming: false })
    property string _lastSys: ""
    function pollSys() {
        if (!sysStatePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastSys) return
                win._lastSys = xhr.responseText
                try {
                    var s = JSON.parse(xhr.responseText)
                    if (s && s.host !== undefined) win.sys = s
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + sysStatePath)
        xhr.send()
    }
    // Both polls live in ONE onCompleted: two Component.onCompleted handlers on
    // the same object is "Property value set multiple times" — a silent death.
    Component.onCompleted: { pollPalette(); pollSys() }
    Timer { interval: 2000; repeat: true; running: true; onTriggered: { win.pollPalette(); win.pollSys() } }

    readonly property var bat: st.battery || null

    // ---- actions --------------------------------------------------------------
    // arm: true = destructive, needs a second tap to fire.
    readonly property var actions: [
        { cmd: "lock",     glyph: icoLock,   label: "Lock",     hint: "L", arm: false, danger: false },
        { cmd: "suspend",  glyph: icoSleep,  label: "Suspend",  hint: "S", arm: false, danger: false },
        { cmd: "logout",   glyph: icoLogout, label: "Log out",  hint: "O", arm: true,  danger: false },
        { cmd: "gaming",   glyph: icoGaming, label: "Return to Gaming", hint: "G", arm: true, danger: false },
        { cmd: "reboot",   glyph: icoReboot, label: "Restart",  hint: "R", arm: true,  danger: true },
        { cmd: "shutdown", glyph: icoOff,    label: "Shut down", hint: "P", arm: true,  danger: true }
    ]

    property int selectedIndex: 0
    property string armed: ""        // cmd waiting for its confirming second tap
    Timer { id: disarm; interval: 4000; onTriggered: win.armed = "" }

    function dismiss() { win.visible = false; quitTimer.start() }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    // ---- command outbox (SQLite polled live by the launcher) -----------------
    function sendCmd(cmd) {
        try {
            var db = LocalStorage.openDatabaseSync("omasteam_power", "1.0", "omasteam power outbox", 100000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS power_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO power_outbox(cmd) VALUES(?)", [cmd])
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
        // separate-event-cycle rule the menu/apps overlays follow.
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

            // ---- hero: host · uptime (+ battery where there is one) ----------
            Item {
                width: parent.width
                height: 44

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: heroPct.left
                    anchors.rightMargin: 10
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.bat ? (win.bat.charging ? win.icoBolt : win.batIcon(win.bat.pct)) : win.icoPower
                        color: win.cAccent
                        font { family: win.fontFamily; pixelSize: 22 }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: win.sys.host ? win.sys.host : "System"
                            color: win.cFg
                            font { family: win.fontFamily; pixelSize: 14; bold: true }
                        }
                        Text {
                            text: {
                                var parts = []
                                if (win.sys.user) parts.push(win.sys.user)
                                if (win.sys.uptime) parts.push(win.sys.uptime)
                                return parts.join(" · ").toUpperCase()
                            }
                            color: win.alpha(win.cFg, 0.55)
                            font { family: win.fontFamily; pixelSize: 11; letterSpacing: 1.1 }
                        }
                    }
                }

                Text {
                    id: heroPct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: win.bat !== null
                    text: win.bat ? win.bat.pct + "%" : ""
                    color: (win.bat && !win.bat.charging && win.bat.pct <= 15) ? win.cDanger : win.cFg
                    font { family: win.fontFamily; pixelSize: 20; bold: true }
                }
            }

            // ---- session actions ---------------------------------------------
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
                                color: (isArmed || sel) ? win.cBg
                                     : (modelData.danger ? win.cDanger : win.cFg)
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
