// omasteam-volume — Omarchy-quattro-style audio panel, in pure QML.
//
// A panel-sized floating card (same recipe as omasteam-apps: explicit
// AnchorNone, static size, no scrim) with an output volume slider, an output
// device picker and a mic slider. Opened from the bar's volume chip.
//
// Same "QML front, bash back" split as the bar/menu/apps: sliders and taps
// push commands to a SQLite outbox (table `vol_outbox`, distinct from the
// bar/menu/apps tables) and the launcher (omasteam-volume), which polls the
// outbox WHILE this window is up, applies them via wpctl/pactl — so volume
// changes are heard live, not on close.
//
// The audio snapshot is rendered in at open (@@VOL@@); the panel then tracks
// its own state optimistically. Height is computed by the launcher (@@H@@)
// from the sink count — the surface size must be static at creation.
import QtQuick
import QtQuick.Window
import QtQuick.LocalStorage
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"
    width: 460
    height: @@H@@

    // Anchored to the top-right so the card pops up under the bar's volume
    // chip (quattro anchors its popup to the bar button; closest layer-shell
    // equivalent). Top|Right only — one edge per axis keeps the fixed size,
    // and the compositor already offsets past the bar's exclusive zone, so
    // margins.top is just the visual gap under the bar.
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

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function g(cp) { return String.fromCodePoint(cp) }
    readonly property string icoVol:     g(0xF028)  // speaker
    readonly property string icoVolLow:  g(0xF027)
    readonly property string icoMute:    g(0xF026)  // speaker-off
    readonly property string icoMic:     g(0xF130)  // microphone
    readonly property string icoMicMute: g(0xF131)  // microphone-slash

    property string _lastRaw: ""
    function poll() {
        if (!statePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastRaw) return
                win._lastRaw = xhr.responseText
                try { win.st = JSON.parse(xhr.responseText) } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + statePath)
        xhr.send()
    }
    Component.onCompleted: poll()

    // ---- audio snapshot (rendered in by the launcher) ------------------------
    // An un-rendered placeholder yields the empty fallback.
    property var init: { var v = @@VOL@@; return (v && v.sinks) ? v : ({ out: { vol: 0, muted: false }, mic: { vol: 0, muted: false }, sinks: [] }) }
    property int  outVol:   init.out.vol
    property bool outMuted: init.out.muted
    property int  micVol:   init.mic.vol
    property bool micMuted: init.mic.muted
    property var  sinks:    init.sinks        // [{ name, label, def }]
    property string defSink: { for (var i = 0; i < init.sinks.length; i++) if (init.sinks[i].def) return init.sinks[i].name; return "" }

    // Cursor rows: 0 = output slider, 1..sinks.length = devices, last = mic.
    property int cursor: 0
    readonly property int rowCount: sinks.length + 2
    function clampPct(v) { return Math.max(0, Math.min(100, Math.round(v))) }

    function dismiss() { win.visible = false; quitTimer.start() }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    // ---- command outbox (SQLite polled live by the launcher) -----------------
    function sendCmd(cmd) {
        try {
            var db = LocalStorage.openDatabaseSync("omasteam_volume", "1.0", "omasteam volume outbox", 100000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS vol_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO vol_outbox(cmd) VALUES(?)", [cmd])
            })
        } catch (e) { console.log("sendCmd failed:", e) }
    }

    function setOut(v)  { outVol = clampPct(v); sendCmd("sink-vol:" + outVol) }
    function setMic(v)  { micVol = clampPct(v); sendCmd("mic-vol:" + micVol) }
    function muteOut()  { outMuted = !outMuted; sendCmd("sink-mute") }
    function muteMic()  { micMuted = !micMuted; sendCmd("mic-mute") }
    function setDefault(name) { defSink = name; sendCmd("default-sink:" + name) }

    function adjust(delta) {
        if (cursor === 0) setOut(outVol + delta)
        else if (cursor === rowCount - 1) setMic(micVol + delta)
    }
    function activate() {
        if (cursor === 0) muteOut()
        else if (cursor === rowCount - 1) muteMic()
        else if (sinks[cursor - 1]) setDefault(sinks[cursor - 1].name)
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 14
        color: win.cBg
        border.color: win.alpha(win.cFg, 0.12)
        border.width: 1
        MouseArea { anchors.fill: parent }

        focus: true
        Keys.onPressed: function(e) {
            switch (e.key) {
            case Qt.Key_Down:   win.cursor = (win.cursor + 1) % win.rowCount;                 e.accepted = true; break
            case Qt.Key_Tab:    win.cursor = (win.cursor + 1) % win.rowCount;                 e.accepted = true; break
            case Qt.Key_Up:     win.cursor = (win.cursor - 1 + win.rowCount) % win.rowCount;  e.accepted = true; break
            case Qt.Key_Left:   win.adjust(-5);  e.accepted = true; break
            case Qt.Key_Right:  win.adjust(5);   e.accepted = true; break
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:  win.activate();  e.accepted = true; break
            case Qt.Key_M:      win.muteOut();   e.accepted = true; break
            case Qt.Key_Escape: win.dismiss();   e.accepted = true; break
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "Output"
                height: 18
                color: win.alpha(win.cFg, 0.55)
                font { family: win.fontFamily; pixelSize: 12; bold: true }
            }

            SliderRow {
                width: parent.width
                value: win.outVol
                muted: win.outMuted
                glyph: win.outMuted ? win.icoMute : (win.outVol < 34 ? win.icoVolLow : win.icoVol)
                active: win.cursor === 0
                onSetValue: function(v) { win.setOut(v) }
                onToggleMute: win.muteOut()
                onFocusMe: win.cursor = 0
            }

            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: win.sinks
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: parent.width
                        height: 36
                        radius: 9
                        readonly property bool sel: win.cursor === index + 1
                        color: sel ? win.cAccent : (devHover.hovered ? win.alpha(win.cFg, 0.08) : "transparent")

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                text: modelData.name === win.defSink ? "●" : "○"
                                color: sel ? win.cBg : win.cAccent
                                font { family: win.fontFamily; pixelSize: 13 }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 30
                                text: modelData.label || modelData.name
                                elide: Text.ElideRight
                                color: sel ? win.cBg : win.cFg
                                font { family: win.fontFamily; pixelSize: 13; bold: sel }
                            }
                        }

                        HoverHandler { id: devHover }
                        TapHandler { onTapped: { win.cursor = index + 1; win.setDefault(modelData.name) } }
                    }
                }
            }

            Text {
                text: "Input"
                height: 18
                color: win.alpha(win.cFg, 0.55)
                font { family: win.fontFamily; pixelSize: 12; bold: true }
            }

            SliderRow {
                width: parent.width
                value: win.micVol
                muted: win.micMuted
                glyph: win.micMuted ? win.icoMicMute : win.icoMic
                active: win.cursor === win.rowCount - 1
                onSetValue: function(v) { win.setMic(v) }
                onToggleMute: win.muteMic()
                onFocusMe: win.cursor = win.rowCount - 1
            }
        }
    }

    // ---- slider row: mute glyph + track + percent ----------------------------
    // Drag sends at most one command per throttle tick (120 ms) plus a final
    // one on release, so wpctl isn't hammered while the handle moves.
    component SliderRow: Item {
        id: srow
        property int value: 0
        property bool muted: false
        property string glyph: ""
        property bool active: false
        signal setValue(int v)
        signal toggleMute()
        signal focusMe()
        height: 44

        property int shown: value          // display value while dragging
        property bool dragging: false
        onValueChanged: if (!dragging) shown = value

        Timer {
            id: throttle
            interval: 120
            onTriggered: srow.setValue(srow.shown)
        }

        Row {
            anchors.fill: parent
            spacing: 12

            Rectangle {
                width: 36; height: 36
                anchors.verticalCenter: parent.verticalCenter
                radius: 9
                color: muteHover.hovered ? win.alpha(win.cFg, 0.08) : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: srow.glyph
                    color: srow.muted ? win.alpha(win.cFg, 0.4) : (srow.active ? win.cAccent : win.cFg)
                    font { family: win.fontFamily; pixelSize: 16 }
                }
                HoverHandler { id: muteHover }
                TapHandler { onTapped: { srow.focusMe(); srow.toggleMute() } }
            }

            Item {
                id: track
                width: parent.width - 36 - 44 - 24   // minus glyph, pct label, spacings
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {                            // groove
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: win.alpha(win.cFg, 0.15)
                }
                Rectangle {                            // fill
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * srow.shown / 100
                    height: 6
                    radius: 3
                    color: srow.muted ? win.alpha(win.cFg, 0.35) : win.cAccent
                }
                Rectangle {                            // handle
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width * srow.shown / 100 - width / 2
                    width: 16; height: 16
                    radius: 8
                    color: srow.active || srow.dragging ? win.cAccent : win.cFg
                    border.color: win.cBg
                    border.width: 2
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: function(m) {
                        srow.focusMe()
                        srow.dragging = true
                        srow.shown = win.clampPct(m.x / track.width * 100)
                        throttle.restart()
                    }
                    onPositionChanged: function(m) {
                        if (!srow.dragging) return
                        srow.shown = win.clampPct(m.x / track.width * 100)
                        if (!throttle.running) throttle.start()
                    }
                    onReleased: {
                        srow.dragging = false
                        throttle.stop()
                        srow.setValue(srow.shown)
                    }
                }
            }

            Text {
                width: 44
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: srow.shown + "%"
                color: srow.muted ? win.alpha(win.cFg, 0.4) : win.cFg
                font { family: win.fontFamily; pixelSize: 13 }
            }
        }
    }
}
