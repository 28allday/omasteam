// omasteam-network — Omarchy-quattro-style network panel, in pure QML.
//
// Opened from the bar's network chip; anchored top-right under it (same
// layer-shell recipe as omasteam-volume: Top|Right + margins, static size).
//
// Hero row shows the active connection (SSID + band, or wired + link speed)
// with a Wi-Fi on/off toggle; below it a scannable Wi-Fi list — tap a network
// to connect (inline password row appears for secured networks that have no
// saved profile), tap the active network to disconnect.
//
// Same "QML front, bash back" split as the rest: actions go to the
// `net_outbox` SQLite table; the launcher (omasteam-network) polls it live
// and drives nmcli. Because connects take seconds, the launcher also keeps a
// net-state.json fresh while the panel is up and this QML re-polls it, so
// rows flip to "connected" on their own.
import QtQuick
import QtQuick.Window
import QtQuick.LocalStorage
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"
    width: 460
    height: 408

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
    readonly property string netStatePath: { var p = "@@NETSTATE@@"; return p.charAt(0) === "/" ? p : "" }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function g(cp) { return String.fromCodePoint(cp) }
    readonly property var icoSignal: [g(0xF092F), g(0xF091F), g(0xF0922), g(0xF0925), g(0xF0928)]
    readonly property string icoWifiOff: g(0xF092E)
    readonly property string icoEth:     g(0xF0200)
    readonly property string icoLock:    g(0xF023)
    function signalGlyph(s) {
        var i = Math.max(0, Math.min(4, Math.ceil(s / 20) - 1))
        return icoSignal[i]
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
    Component.onCompleted: { pollPalette(); pollNet() }

    // ---- network state (net-state.json, kept fresh by the launcher) ----------
    // net = { wifi: bool, conn: { type, label, detail, signal }, nets: [...] }
    // nets rows: { ssid, signal, secured, known, active }
    property var net: ({ wifi: true, conn: { type: "none", label: "", detail: "", signal: 0 }, nets: [] })
    property string _lastNet: ""
    function pollNet() {
        if (!netStatePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastNet) return
                win._lastNet = xhr.responseText
                try {
                    var n = JSON.parse(xhr.responseText)
                    if (n && n.nets) {
                        win.net = n
                        // A network turning active means the pending connect landed.
                        if (win.connecting !== "") {
                            for (var i = 0; i < n.nets.length; i++)
                                if (n.nets[i].ssid === win.connecting && n.nets[i].active) win.connecting = ""
                        }
                    }
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + netStatePath)
        xhr.send()
    }
    Timer { interval: 1500; repeat: true; running: true; onTriggered: win.pollNet() }

    property int selectedIndex: 0
    property string pwFor: ""        // SSID awaiting a password in the input row
    property string connecting: ""   // SSID with a connect in flight
    Timer { id: connectingTimeout; interval: 20000; onTriggered: win.connecting = "" }

    function dismiss() { win.visible = false; quitTimer.start() }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    // ---- command outbox (SQLite polled live by the launcher) -----------------
    function sendCmd(cmd) {
        try {
            var db = LocalStorage.openDatabaseSync("omasteam_network", "1.0", "omasteam network outbox", 100000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS net_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO net_outbox(cmd) VALUES(?)", [cmd])
            })
        } catch (e) { console.log("sendCmd failed:", e) }
    }

    function toggleWifi() {
        var on = !(net.wifi === true)
        var n = net; n.wifi = on; net = n   // optimistic
        sendCmd(on ? "wifi-on" : "wifi-off")
    }
    function startConnecting(ssid) {
        connecting = ssid; connectingTimeout.restart()
    }
    function activate(row) {
        if (!row) return
        pwFor = ""
        if (row.active) { sendCmd("disconnect"); return }
        if (row.secured && !row.known) {
            pwFor = row.ssid
            pwInput.text = ""
            pwInput.forceActiveFocus()
            return
        }
        startConnecting(row.ssid)
        sendCmd("connect:" + Qt.btoa(row.ssid))
    }
    function submitPassword() {
        if (pwFor === "" || pwInput.text.length === 0) return
        startConnecting(pwFor)
        sendCmd("connect-pw:" + Qt.btoa(pwFor) + ":" + Qt.btoa(pwInput.text))
        pwFor = ""; pwInput.text = ""
        keys.forceActiveFocus()
    }
    function moveSel(d) {
        var n = net.nets.length
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
                case Qt.Key_Down:   win.moveSel(1);   e.accepted = true; break
                case Qt.Key_Tab:    win.moveSel(1);   e.accepted = true; break
                case Qt.Key_Up:     win.moveSel(-1);  e.accepted = true; break
                case Qt.Key_Return:
                case Qt.Key_Enter:  win.activate(win.net.nets[win.selectedIndex]); e.accepted = true; break
                case Qt.Key_T:      win.toggleWifi(); e.accepted = true; break
                case Qt.Key_R:      win.sendCmd("rescan"); e.accepted = true; break
                case Qt.Key_Escape: win.dismiss();    e.accepted = true; break
                }
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ---- hero: active connection + wifi toggle -----------------------
            Item {
                width: parent.width
                height: 44

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.net.conn.type === "ethernet" ? win.icoEth
                            : win.net.conn.type === "wifi"     ? win.signalGlyph(win.net.conn.signal)
                            : win.net.wifi === true            ? win.icoSignal[0] : win.icoWifiOff
                        color: win.net.conn.type === "none" ? win.alpha(win.cFg, 0.4) : win.cAccent
                        font { family: win.fontFamily; pixelSize: 22 }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: win.net.conn.type === "none" ? "Not connected" : win.net.conn.label
                            color: win.cFg
                            font { family: win.fontFamily; pixelSize: 14; bold: true }
                        }
                        Text {
                            text: win.net.conn.type === "ethernet" ? ("wired" + (win.net.conn.detail ? " · " + win.net.conn.detail : ""))
                                : win.net.conn.type === "wifi"     ? (win.net.conn.detail || "wifi")
                                : win.net.wifi === true            ? "wifi on" : "wifi off"
                            color: win.alpha(win.cFg, 0.55)
                            font { family: win.fontFamily; pixelSize: 11 }
                        }
                    }
                }

                // Wi-Fi on/off toggle pill
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 22
                    radius: 11
                    color: win.net.wifi === true ? win.cAccent : win.alpha(win.cFg, 0.2)
                    Rectangle {
                        width: 16; height: 16
                        radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: win.net.wifi === true ? parent.width - width - 3 : 3
                        color: win.cBg
                        Behavior on x { NumberAnimation { duration: 120 } }
                    }
                    TapHandler { onTapped: win.toggleWifi() }
                }
            }

            // ---- wifi list ---------------------------------------------------
            ListView {
                id: list
                width: parent.width
                readonly property int rowH: 36
                height: 8 * rowH                 // constant card: list scrolls
                model: win.net.nets
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
                            text: win.signalGlyph(modelData.signal)
                            color: sel ? win.cBg : (modelData.active ? win.cAccent : win.cFg)
                            font { family: win.fontFamily; pixelSize: 15 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 22 - 90 - 24
                            text: modelData.ssid
                            elide: Text.ElideRight
                            color: sel ? win.cBg : (modelData.active ? win.cAccent : win.cFg)
                            font { family: win.fontFamily; pixelSize: 13; bold: modelData.active === true }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 90
                            horizontalAlignment: Text.AlignRight
                            text: modelData.active ? "connected"
                                : win.connecting === modelData.ssid ? "connecting…"
                                : modelData.secured ? win.icoLock : ""
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
                    visible: win.net.nets.length === 0
                    text: win.net.wifi === true ? "Scanning…" : "Wi-Fi is off"
                    color: win.alpha(win.cFg, 0.4)
                    font { family: win.fontFamily; pixelSize: 13 }
                }
            }

            // ---- password row (fixed slot so the card never resizes) ---------
            Item {
                width: parent.width
                height: 36

                Rectangle {
                    anchors.fill: parent
                    visible: win.pwFor !== ""
                    radius: 9
                    color: win.alpha(win.cFg, 0.06)

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.icoLock
                            color: win.alpha(win.cFg, 0.55)
                            font { family: win.fontFamily; pixelSize: 13 }
                        }
                        TextInput {
                            id: pwInput
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 40
                            color: win.cFg
                            echoMode: TextInput.Password
                            selectByMouse: true
                            clip: true
                            font { family: win.fontFamily; pixelSize: 13 }
                            cursorDelegate: Rectangle { width: 2; color: win.cAccent }
                            onAccepted: win.submitPassword()
                            Keys.onEscapePressed: {
                                win.pwFor = ""; pwInput.text = ""
                                keys.forceActiveFocus()
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: pwInput.text.length === 0
                                text: "Password for " + win.pwFor + " — Enter to connect"
                                elide: Text.ElideRight
                                width: parent.width
                                color: win.alpha(win.cFg, 0.4)
                                font { family: win.fontFamily; pixelSize: 12 }
                            }
                        }
                    }
                }
            }
        }
    }
}
