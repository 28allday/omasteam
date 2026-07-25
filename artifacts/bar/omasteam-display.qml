// omasteam-display — Omarchy-quattro-style display panel, in pure QML.
//
// Opened from the system menu's "Display & Monitor > Display Configuration"
// leaf, in place of kcmshell6 kcm_kscreen. Same card shape as the bar's panels
// (Top|Right + margins, static size), same QML-front / bash-back split: taps go
// to the `disp_outbox` SQLite table and the launcher (omasteam-display) drives
// kscreen-doctor and keeps disp-state.json fresh.
//
// Resolution / scale / rotation are APPLIED ON APPROVAL — the launcher reverts
// them unless the confirm strip is tapped, because a bad mode on a display you
// can no longer see is not something a user can undo from here.
//
// Height is computed by the launcher (@@H@@): an output picker only appears with
// more than one display, a brightness row only with a real backlight.
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
    readonly property string dspStatePath: { var p = "@@DSPSTATE@@"; return p.charAt(0) === "/" ? p : "" }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function g(cp) { return String.fromCodePoint(cp) }
    readonly property string icoDisplay: g(0xF108)   // fa-desktop
    readonly property string icoStar:    g(0xF005)   // fa-star — primary output
    readonly property string icoSun:     g(0xF185)   // fa-sun

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

    // ---- display state (disp-state.json, kept fresh by the launcher) ---------
    property var dsp: ({ outputs: [], backlight: { present: false, pct: 0 }, pending: null })
    property string _lastDsp: ""
    function pollDsp() {
        if (!dspStatePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastDsp) return
                win._lastDsp = xhr.responseText
                try {
                    var d = JSON.parse(xhr.responseText)
                    if (d && d.outputs) {
                        // Defensive fill, like the other panels: a missing key
                        // must never reach a binding as undefined.
                        win.dsp = {
                            outputs: d.outputs,
                            backlight: d.backlight || { present: false, pct: 0 },
                            pending: d.pending || null
                        }
                        if (!win.dragBright && win.dsp.backlight.present) win.brightShown = win.dsp.backlight.pct
                    }
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + dspStatePath)
        xhr.send()
    }
    Component.onCompleted: { pollPalette(); pollDsp() }
    Timer { interval: 500; repeat: true; running: true; onTriggered: { win.pollDsp(); win.pollPalette() } }

    // ---- selection ----------------------------------------------------------
    // Tracked by NAME, not index: the launcher rewrites the whole outputs array
    // every refresh and a hotplug would otherwise slide the selection sideways.
    property string selectedName: ""
    readonly property var out: {
        var o = dsp.outputs
        if (!o || o.length === 0) return null
        for (var i = 0; i < o.length; i++) if (o[i].name === selectedName) return o[i]
        for (var j = 0; j < o.length; j++) if (o[j].primary) return o[j]
        return o[0]
    }
    readonly property var modes: out && out.modes ? out.modes : []
    readonly property bool pending: dsp.pending !== null && dsp.pending !== undefined

    readonly property var scalePresets: [1, 1.25, 1.5, 1.75, 2, 2.25]
    readonly property var rotations: [
        { id: "none",     label: "Normal" },
        { id: "left",     label: "90° L" },
        { id: "right",    label: "90° R" },
        { id: "inverted", label: "180°" }
    ]

    property int modeIndex: 0
    property int brightShown: 0
    property bool dragBright: false

    function dismiss() { win.visible = false; quitTimer.start() }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    // ---- command outbox (SQLite polled live by the launcher) -----------------
    function sendCmd(cmd) {
        try {
            var db = LocalStorage.openDatabaseSync("omasteam_display", "1.0", "omasteam display outbox", 100000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS disp_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO disp_outbox(cmd) VALUES(?)", [cmd])
            })
        } catch (e) { console.log("sendCmd failed:", e) }
    }

    function applyMode(m)   { if (out && m) sendCmd("mode:" + out.name + ":" + m.id) }
    function applyScale(s)  { if (out) sendCmd("scale:" + out.name + ":" + s) }
    function applyRot(r)    { if (out) sendCmd("rot:" + out.name + ":" + r) }
    function makePrimary()  { if (out && !out.primary) sendCmd("primary:" + out.name) }
    function toggleEnabled() {
        if (!out) return
        // The launcher refuses to disable the last enabled output; don't even
        // offer it here.
        if (out.enabled && enabledCount() <= 1) return
        sendCmd("enable:" + out.name + ":" + (out.enabled ? "0" : "1"))
    }
    function enabledCount() {
        var n = 0
        for (var i = 0; i < dsp.outputs.length; i++) if (dsp.outputs[i].enabled) n++
        return n
    }
    function setBright(v) {
        brightShown = Math.max(0, Math.min(100, Math.round(v)))
        brightThrottle.restart()
    }
    Timer { id: brightThrottle; interval: 150; onTriggered: win.sendCmd("bright:" + win.brightShown) }

    function cycleOutput(d) {
        var o = dsp.outputs
        if (!o || o.length < 2) return
        var cur = 0
        for (var i = 0; i < o.length; i++) if (out && o[i].name === out.name) cur = i
        selectedName = o[(cur + d + o.length) % o.length].name
        modeIndex = 0
    }
    function moveMode(d) {
        if (modes.length === 0) return
        modeIndex = (modeIndex + d + modes.length) % modes.length
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
                case Qt.Key_Down:   win.moveMode(1);  e.accepted = true; break
                case Qt.Key_Up:     win.moveMode(-1); e.accepted = true; break
                case Qt.Key_Tab:    win.cycleOutput(1); e.accepted = true; break
                case Qt.Key_Return:
                case Qt.Key_Enter:  win.applyMode(win.modes[win.modeIndex]); e.accepted = true; break
                case Qt.Key_K:      if (win.pending) win.sendCmd("keep");   e.accepted = true; break
                case Qt.Key_Z:      if (win.pending) win.sendCmd("revert"); e.accepted = true; break
                case Qt.Key_P:      win.makePrimary(); e.accepted = true; break
                case Qt.Key_Escape: win.dismiss(); e.accepted = true; break
                }
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ---- hero: output · mode · scale ---------------------------------
            Item {
                width: parent.width
                height: 44

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: heroRight.left
                    anchors.rightMargin: 10
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.icoDisplay
                        color: (win.out && win.out.enabled) ? win.cAccent : win.alpha(win.cFg, 0.4)
                        font { family: win.fontFamily; pixelSize: 22 }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 22 - parent.spacing
                        spacing: 2
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: win.out ? win.out.name : "No display"
                            color: win.cFg
                            font { family: win.fontFamily; pixelSize: 14; bold: true }
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: {
                                if (!win.out) return ""
                                var parts = [win.out.kind]
                                if (win.out.current) parts.push(win.out.current)
                                if (!win.out.enabled) parts.push("disabled")
                                return parts.join(" · ").toUpperCase()
                            }
                            color: win.alpha(win.cFg, 0.55)
                            font { family: win.fontFamily; pixelSize: 11; letterSpacing: 1.1 }
                        }
                    }
                }

                Row {
                    id: heroRight
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // primary marker / setter
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: win.dsp.outputs.length > 1
                        text: win.icoStar
                        color: (win.out && win.out.primary) ? win.cAccent : win.alpha(win.cFg, 0.3)
                        font { family: win.fontFamily; pixelSize: 15 }
                        TapHandler { onTapped: win.makePrimary() }
                    }

                    // enable toggle — hidden when this is the only display, so
                    // the one control that can black out the machine isn't there
                    // to be mis-tapped.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: win.dsp.outputs.length > 1
                        width: 44; height: 22
                        radius: 11
                        color: (win.out && win.out.enabled) ? win.cAccent : win.alpha(win.cFg, 0.2)
                        Rectangle {
                            width: 16; height: 16
                            radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            x: (win.out && win.out.enabled) ? parent.width - width - 3 : 3
                            color: win.cBg
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                        TapHandler { onTapped: win.toggleEnabled() }
                    }
                }
            }

            // ---- output picker (only with more than one display) -------------
            Row {
                width: parent.width
                height: 32
                spacing: 6
                visible: win.dsp.outputs.length > 1

                Repeater {
                    model: win.dsp.outputs
                    Pill {
                        required property var modelData
                        label: modelData.name
                        active: win.out && win.out.name === modelData.name
                        dim: !modelData.enabled
                        onTapped: { win.selectedName = modelData.name; win.modeIndex = 0 }
                    }
                }
            }

            // ---- resolution --------------------------------------------------
            Column {
                width: parent.width
                spacing: 4

                SectionHeader { text: "RESOLUTION" }

                ListView {
                    id: modeList
                    width: parent.width
                    readonly property int rowH: 32
                    height: 5 * rowH
                    model: win.modes
                    interactive: contentHeight > height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: win.modeIndex

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        height: modeList.rowH
                        radius: 8
                        readonly property bool sel: index === win.modeIndex
                        color: sel ? win.cAccent : (mh.hovered ? win.alpha(win.cFg, 0.08) : "transparent")

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                text: modelData.current ? "●" : "○"
                                color: sel ? win.cBg : win.cAccent
                                font { family: win.fontFamily; pixelSize: 12 }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 16 - 90 - 20
                                elide: Text.ElideRight
                                text: modelData.w + " × " + modelData.h
                                color: sel ? win.cBg : win.cFg
                                font { family: win.fontFamily; pixelSize: 13; bold: modelData.current === true }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 90
                                horizontalAlignment: Text.AlignRight
                                text: modelData.hz + " Hz"
                                color: sel ? win.cBg : win.alpha(win.cFg, 0.5)
                                font { family: win.fontFamily; pixelSize: 11 }
                            }
                        }

                        HoverHandler { id: mh }
                        TapHandler { onTapped: { win.modeIndex = index; win.applyMode(modelData) } }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: win.modes.length === 0
                        text: "No modes reported"
                        color: win.alpha(win.cFg, 0.4)
                        font { family: win.fontFamily; pixelSize: 13 }
                    }
                }
            }

            // ---- scale -------------------------------------------------------
            Column {
                width: parent.width
                spacing: 4

                SectionHeader {
                    // The live value goes in the header: a display can sit on a
                    // fractional scale (1.7 here) that matches no preset pill.
                    text: "SCALE" + (win.out ? "  ·  " + win.out.scale : "")
                }

                Row {
                    width: parent.width
                    height: 30
                    spacing: 6
                    Repeater {
                        model: win.scalePresets
                        Pill {
                            required property var modelData
                            label: String(modelData) + "×"
                            active: win.out && Math.abs(win.out.scale - modelData) < 0.01
                            onTapped: win.applyScale(modelData)
                        }
                    }
                }
            }

            // ---- rotation ----------------------------------------------------
            Column {
                width: parent.width
                spacing: 4

                SectionHeader { text: "ROTATION" }

                Row {
                    width: parent.width
                    height: 30
                    spacing: 6
                    Repeater {
                        model: win.rotations
                        Pill {
                            required property var modelData
                            label: modelData.label
                            active: win.out && win.out.rotation === modelData.id
                            onTapped: win.applyRot(modelData.id)
                        }
                    }
                }
            }

            // ---- brightness (real backlight only) ----------------------------
            Column {
                width: parent.width
                spacing: 4
                visible: win.dsp.backlight.present === true

                SectionHeader { text: "BRIGHTNESS" }

                Item {
                    width: parent.width
                    height: 40

                    Text {
                        id: brightGlyph
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.icoSun
                        color: win.cFg
                        font { family: win.fontFamily; pixelSize: 16 }
                    }

                    Item {
                        id: brightTrack
                        anchors.left: brightGlyph.right
                        anchors.leftMargin: 12
                        anchors.right: brightPct.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 6; radius: 3
                            color: win.alpha(win.cFg, 0.15)
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * win.brightShown / 100
                            height: 6; radius: 3
                            color: win.cAccent
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width * win.brightShown / 100 - width / 2
                            width: 16; height: 16; radius: 8
                            color: win.dragBright ? win.cAccent : win.cFg
                            border.color: win.cBg
                            border.width: 2
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: function(m) {
                                win.dragBright = true
                                win.setBright(m.x / brightTrack.width * 100)
                            }
                            onPositionChanged: function(m) {
                                if (win.dragBright) win.setBright(m.x / brightTrack.width * 100)
                            }
                            onReleased: {
                                win.dragBright = false
                                win.sendCmd("bright:" + win.brightShown)
                            }
                        }
                    }

                    Text {
                        id: brightPct
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        horizontalAlignment: Text.AlignRight
                        text: win.brightShown + "%"
                        color: win.cFg
                        font { family: win.fontFamily; pixelSize: 13 }
                    }
                }
            }
        }

        // ---- pending-approval strip ------------------------------------------
        // Floats over the bottom of the card: the surface size is fixed at
        // creation, so this must not take part in the layout.
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                      leftMargin: 8; rightMargin: 8; bottomMargin: 8 }
            height: 44
            radius: 10
            visible: win.pending
            color: win.cDanger

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 150
                    elide: Text.ElideRight
                    text: {
                        if (!win.pending) return ""
                        var s = win.dsp.pending.secs
                        return "Keep this " + (win.dsp.pending.label || "change") + "? Reverting in " + s + "s"
                    }
                    color: win.cBg
                    font { family: win.fontFamily; pixelSize: 12; bold: true }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 62; height: 28
                    radius: 8
                    color: win.cBg
                    Text {
                        anchors.centerIn: parent
                        text: "Keep"
                        color: win.cFg
                        font { family: win.fontFamily; pixelSize: 12; bold: true }
                    }
                    TapHandler { onTapped: win.sendCmd("keep") }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 62; height: 28
                    radius: 8
                    color: win.alpha(win.cBg, 0.35)
                    Text {
                        anchors.centerIn: parent
                        text: "Revert"
                        color: win.cBg
                        font { family: win.fontFamily; pixelSize: 12; bold: true }
                    }
                    TapHandler { onTapped: win.sendCmd("revert") }
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
            color: pill.active ? win.cBg : win.alpha(win.cFg, pill.dim ? 0.4 : 0.85)
            font { family: win.fontFamily; pixelSize: 12; bold: pill.active }
        }

        HoverHandler { id: ph }
        TapHandler { onTapped: pill.tapped() }
    }
}
