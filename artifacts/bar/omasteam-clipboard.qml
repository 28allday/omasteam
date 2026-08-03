// omasteam-clipboard — clipboard history panel, in pure QML.
//
// Opened from the bar's clipboard chip; anchored top-right under it (same
// layer-shell recipe as the other panels: Top|Right + margins, static size).
//
// The history is Plasma's (see bin/omasteam-clipboard for why a hidden helper
// keeps the org.kde.klipper interface alive). Tapping an entry makes it the
// current clipboard contents; "Clear history" is armed and needs a second tap,
// because it is not recoverable.
//
// Same split as the other panels: actions go to the `clip_outbox` SQLite table
// and the launcher (omasteam-clipboard) polls it live and runs the verb.
import QtQuick
import QtQuick.Window
import QtQuick.LocalStorage
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"
    width: 480
    height: 440

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
    readonly property string clStatePath: { var p = "@@CLSTATE@@"; return p.charAt(0) === "/" ? p : "" }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function g(cp) { return String.fromCodePoint(cp) }
    readonly property string icoClip:  g(0xF0EA)   // fa-clipboard
    readonly property string icoTrash: g(0xF014)   // fa-trash-o

    // A history entry is arbitrary text: it can be many lines, or mostly
    // whitespace. Flatten to one line for the row, and mark how much was hidden.
    function flatten(t) {
        if (!t) return ""
        return t.replace(/\s+/g, " ").trim()
    }
    function lineCount(t) {
        if (!t) return 0
        return t.split("\n").length
    }

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

    // ---- clipboard history (clip-state.json, refreshed by the launcher) -------
    property var items: []
    property string _lastCl: ""
    function pollClip() {
        if (!clStatePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastCl) return
                win._lastCl = xhr.responseText
                try {
                    var c = JSON.parse(xhr.responseText)
                    if (c && c.items !== undefined) {
                        win.items = c.items
                        if (win.selectedIndex >= win.items.length)
                            win.selectedIndex = Math.max(0, win.items.length - 1)
                    }
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + clStatePath)
        xhr.send()
    }
    // Both polls in ONE onCompleted: two Component.onCompleted handlers on the
    // same object is "Property value set multiple times" — a silent death.
    Component.onCompleted: { pollPalette(); pollClip() }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: { win.pollPalette(); win.pollClip() } }

    property int selectedIndex: 0
    property bool armedClear: false
    Timer { id: disarm; interval: 4000; onTriggered: win.armedClear = false }

    function dismiss() { win.visible = false; quitTimer.start() }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    // ---- command outbox (SQLite polled live by the launcher) -----------------
    function sendCmd(cmd) {
        try {
            var db = LocalStorage.openDatabaseSync("omasteam_clipboard", "1.0", "omasteam clipboard outbox", 100000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS clip_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO clip_outbox(cmd) VALUES(?)", [cmd])
            })
        } catch (e) { console.log("sendCmd failed:", e) }
    }

    function pick(i) {
        if (i < 0 || i >= win.items.length) return
        win.sendCmd("pick:" + win.items[i].i)
        win.dismiss()
    }
    function clearAll() {
        if (!win.armedClear) { win.armedClear = true; disarm.restart(); return }
        win.armedClear = false; disarm.stop()
        win.sendCmd("clear")
        win.dismiss()
    }
    function moveSel(d) {
        var n = win.items.length
        if (n === 0) return
        win.selectedIndex = (win.selectedIndex + d + n) % n
        list.positionViewAtIndex(win.selectedIndex, ListView.Contain)
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
                case Qt.Key_Enter:  win.pick(win.selectedIndex); e.accepted = true; break
                case Qt.Key_Delete: win.clearAll(); e.accepted = true; break
                case Qt.Key_Escape: win.dismiss(); e.accepted = true; break
                default:
                    // 1-9 jump straight to an entry, like the menu's key hints.
                    if (e.text >= "1" && e.text <= "9") {
                        win.pick(parseInt(e.text) - 1); e.accepted = true
                    }
                    break
                }
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ---- hero ---------------------------------------------------------
            Item {
                width: parent.width
                height: 40

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.icoClip
                        color: win.cAccent
                        font { family: win.fontFamily; pixelSize: 20 }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Clipboard"
                            color: win.cFg
                            font { family: win.fontFamily; pixelSize: 14; bold: true }
                        }
                        Text {
                            text: win.items.length === 0 ? "EMPTY"
                                : (win.items.length + (win.items.length === 1 ? " ENTRY" : " ENTRIES"))
                            color: win.alpha(win.cFg, 0.55)
                            font { family: win.fontFamily; pixelSize: 11; letterSpacing: 1.1 }
                        }
                    }
                }

                // Clear history — armed, because it cannot be undone.
                Rectangle {
                    id: clearBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: win.items.length > 0
                    width: clearRow.implicitWidth + 20
                    height: 26
                    radius: 7
                    color: win.armedClear ? win.cDanger
                         : (clearHover.hovered ? win.alpha(win.cFg, 0.10) : "transparent")
                    Row {
                        id: clearRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.icoTrash
                            color: win.armedClear ? win.cBg : win.alpha(win.cFg, 0.7)
                            font { family: win.fontFamily; pixelSize: 12 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.armedClear ? "Tap again" : "Clear"
                            color: win.armedClear ? win.cBg : win.alpha(win.cFg, 0.7)
                            font { family: win.fontFamily; pixelSize: 11; bold: win.armedClear }
                        }
                    }
                    HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: win.clearAll() }
                }
            }

            // ---- history ------------------------------------------------------
            Text {
                visible: win.items.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Nothing copied yet"
                color: win.alpha(win.cFg, 0.45)
                font { family: win.fontFamily; pixelSize: 12 }
            }

            ListView {
                id: list
                visible: win.items.length > 0
                width: parent.width
                height: parent.height - 48
                clip: true
                model: win.items
                spacing: 0
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: win.selectedIndex

                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    width: ListView.view.width
                    height: 42
                    radius: 9
                    readonly property bool sel: index === win.selectedIndex
                    color: sel ? win.cAccent
                         : (rowHover.hovered ? win.alpha(win.cFg, 0.08) : "transparent")

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        // 1-9 hint, matching the keyboard shortcut above.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            text: index < 9 ? (index + 1) : ""
                            color: sel ? win.alpha(win.cBg, 0.7) : win.alpha(win.cFg, 0.35)
                            font { family: win.fontFamily; pixelSize: 11 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 16 - 52 - 20
                            text: win.flatten(modelData.text)
                            elide: Text.ElideRight
                            color: sel ? win.cBg : win.cFg
                            font { family: win.fontFamily; pixelSize: 12 }
                        }
                        // Multi-line entries flatten to one row, so say how many
                        // lines were folded away rather than silently hiding them.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 52
                            horizontalAlignment: Text.AlignRight
                            visible: win.lineCount(modelData.text) > 1
                            text: win.lineCount(modelData.text) + " lines"
                            color: sel ? win.alpha(win.cBg, 0.7) : win.alpha(win.cFg, 0.4)
                            font { family: win.fontFamily; pixelSize: 10 }
                        }
                    }

                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { win.selectedIndex = index; win.pick(index) } }
                }
            }
        }
    }
}
