// omasteam-bluetooth — Omarchy-quattro-style bluetooth panel, in pure QML.
//
// Opened from the bar's bluetooth chip; anchored top-right under it (same
// layer-shell recipe as the volume/network panels: Top|Right + margins,
// static size).
//
// Hero row shows the adapter state (or the connected device) with a power
// toggle; below it the device list — connected first, then paired, then
// anything discovered by a scan. Tap to connect/disconnect; unpaired
// devices are paired+trusted+connected in one go.
//
// Same split as the network panel: actions go to the `bt_outbox` SQLite
// table, the launcher (omasteam-bluetooth) polls it live and drives
// bluetoothctl, and keeps bt-state.json fresh so rows flip to "connected"
// on their own.
import QtQuick
import QtQuick.Window
import QtQuick.LocalStorage
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"
    width: 460
    height: 364

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
    readonly property string btStatePath: { var p = "@@BTSTATE@@"; return p.charAt(0) === "/" ? p : "" }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function g(cp) { return String.fromCodePoint(cp) }
    readonly property string icoBt:     g(0xF00AF)  // md-bluetooth
    readonly property string icoBtConn: g(0xF00B1)  // md-bluetooth-connect
    readonly property string icoBtOff:  g(0xF00B2)  // md-bluetooth-off

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

    // ---- bluetooth state (bt-state.json, kept fresh by the launcher) ---------
    // bt = { powered: bool, scanning: bool, devs: [{ mac, label, paired, connected }] }
    property var bt: ({ powered: false, scanning: false, devs: [] })
    property string _lastBt: ""
    function pollBt() {
        if (!btStatePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastBt) return
                win._lastBt = xhr.responseText
                try {
                    var b = JSON.parse(xhr.responseText)
                    if (b && b.devs) {
                        win.bt = b
                        if (win.connecting !== "") {
                            for (var i = 0; i < b.devs.length; i++)
                                if (b.devs[i].mac === win.connecting && b.devs[i].connected) win.connecting = ""
                        }
                    }
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + btStatePath)
        xhr.send()
    }
    Component.onCompleted: { pollPalette(); pollBt() }
    Timer { interval: 1500; repeat: true; running: true; onTriggered: win.pollBt() }

    readonly property var connectedDev: {
        for (var i = 0; i < bt.devs.length; i++) if (bt.devs[i].connected) return bt.devs[i]
        return null
    }

    property int selectedIndex: 0
    property string connecting: ""   // MAC with a connect/pair in flight
    Timer { id: connectingTimeout; interval: 25000; onTriggered: win.connecting = "" }

    function dismiss() { win.visible = false; quitTimer.start() }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    // ---- command outbox (SQLite polled live by the launcher) -----------------
    function sendCmd(cmd) {
        try {
            var db = LocalStorage.openDatabaseSync("omasteam_bluetooth", "1.0", "omasteam bluetooth outbox", 100000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS bt_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO bt_outbox(cmd) VALUES(?)", [cmd])
            })
        } catch (e) { console.log("sendCmd failed:", e) }
    }

    function togglePower() {
        var on = !(bt.powered === true)
        var b = bt; b.powered = on; bt = b   // optimistic
        sendCmd(on ? "bt-on" : "bt-off")
    }
    function activate(row) {
        if (!row) return
        if (row.connected) { sendCmd("disconnect:" + row.mac); return }
        connecting = row.mac; connectingTimeout.restart()
        sendCmd((row.paired ? "connect:" : "pair:") + row.mac)
    }
    function moveSel(d) {
        var n = bt.devs.length
        if (n === 0) return
        selectedIndex = (selectedIndex + d + n) % n
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
                case Qt.Key_Down:   win.moveSel(1);     e.accepted = true; break
                case Qt.Key_Tab:    win.moveSel(1);     e.accepted = true; break
                case Qt.Key_Up:     win.moveSel(-1);    e.accepted = true; break
                case Qt.Key_Return:
                case Qt.Key_Enter:  win.activate(win.bt.devs[win.selectedIndex]); e.accepted = true; break
                case Qt.Key_T:      win.togglePower();  e.accepted = true; break
                case Qt.Key_R:      win.sendCmd("scan"); e.accepted = true; break
                case Qt.Key_Escape: win.dismiss();      e.accepted = true; break
                }
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ---- hero: adapter / connected device + power toggle -------------
            Item {
                width: parent.width
                height: 44

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.bt.powered !== true ? win.icoBtOff
                            : win.connectedDev ? win.icoBtConn : win.icoBt
                        color: win.bt.powered !== true ? win.alpha(win.cFg, 0.4) : win.cAccent
                        font { family: win.fontFamily; pixelSize: 22 }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: win.connectedDev ? win.connectedDev.label : "Bluetooth"
                            color: win.cFg
                            font { family: win.fontFamily; pixelSize: 14; bold: true }
                        }
                        Text {
                            readonly property int paired: {
                                var n = 0
                                for (var i = 0; i < win.bt.devs.length; i++) if (win.bt.devs[i].paired) n++
                                return n
                            }
                            text: win.bt.powered !== true ? "off"
                                : (win.bt.scanning ? "scanning…"
                                   : "on · " + paired + " paired")
                            color: win.alpha(win.cFg, 0.55)
                            font { family: win.fontFamily; pixelSize: 11 }
                        }
                    }
                }

                // power toggle pill
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 22
                    radius: 11
                    color: win.bt.powered === true ? win.cAccent : win.alpha(win.cFg, 0.2)
                    Rectangle {
                        width: 16; height: 16
                        radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: win.bt.powered === true ? parent.width - width - 3 : 3
                        color: win.cBg
                        Behavior on x { NumberAnimation { duration: 120 } }
                    }
                    TapHandler { onTapped: win.togglePower() }
                }
            }

            // ---- device list -------------------------------------------------
            ListView {
                id: list
                width: parent.width
                readonly property int rowH: 36
                height: 8 * rowH                 // constant card: list scrolls
                model: win.bt.devs
                interactive: contentHeight > height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: win.selectedIndex

                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    width: ListView.view.width
                    height: list.rowH
                    radius: 9
                    readonly property bool sel: index === win.selectedIndex
                    color: sel ? win.cAccent : (rowHover.hovered ? win.alpha(win.cFg, 0.08) : "transparent")

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            text: modelData.connected ? win.icoBtConn : win.icoBt
                            color: sel ? win.cBg : (modelData.connected ? win.cAccent : win.cFg)
                            font { family: win.fontFamily; pixelSize: 15 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 22 - 100 - 24
                            text: modelData.label
                            elide: Text.ElideRight
                            color: sel ? win.cBg : (modelData.connected ? win.cAccent : win.cFg)
                            font { family: win.fontFamily; pixelSize: 13; bold: modelData.connected === true }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 100
                            horizontalAlignment: Text.AlignRight
                            text: modelData.connected ? "connected"
                                : win.connecting === modelData.mac ? "connecting…"
                                : modelData.paired ? "paired" : "new"
                            color: sel ? win.cBg : win.alpha(win.cFg, 0.5)
                            font { family: win.fontFamily; pixelSize: 11 }
                        }
                    }

                    HoverHandler { id: rowHover }
                    TapHandler {
                        onTapped: { win.selectedIndex = index; win.activate(modelData) }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: win.bt.devs.length === 0
                    text: win.bt.powered !== true ? "Bluetooth is off"
                        : (win.bt.scanning ? "Scanning…" : "No devices — R to scan")
                    color: win.alpha(win.cFg, 0.4)
                    font { family: win.fontFamily; pixelSize: 13 }
                }
            }
        }
    }
}
