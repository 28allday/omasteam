// omasteam-apps — a separate Omarchy-style application launcher, in pure QML.
//
// Companion to omasteam-menu (which is the system-settings surface). This one is
// JUST the app grid/list: a walker-style, type-to-filter picker over the desktop
// entries on the system. Bound to Meta+Space and to the bar's apps button.
//
// Same "QML front, bash back" split as the bar/menu: plain qmlscene can't spawn
// processes, so the chosen .desktop path is pushed to a SQLite outbox and the
// launcher (omasteam-apps, which waits for this window to close) launches it.
//
// The outbox table is `apps_outbox` — distinct from the bar's `outbox` and the
// menu's `menu_outbox`, so no backend drains another's commands.
import QtQuick
import QtQuick.Window
import QtQuick.LocalStorage
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"
    // Explicit full-screen size — a plain qmlscene Window with org.kde.layershell
    // does NOT derive its size from the all-edge anchors (unlike Quickshell's
    // PanelWindow); without this it falls back to a centered ~3/4 box and the
    // scrim leaves a transparent margin. (See omasteam-menu.qml for the full note.)
    width: Screen.width
    height: Screen.height

    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
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
    readonly property string icoSearch: g(0xF002)  // magnifier
    readonly property string icoApp:    g(0xF135)  // rocket (generic app glyph)

    // Poll the palette ONCE at open (see omasteam-menu.qml: repeated repaints
    // accumulate the scrim on this transparent overlay). The launcher is transient.
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

    // ---- app list ------------------------------------------------------------
    // The launcher renders @@APPS@@ to a JSON array of { label, action } (action
    // is `launch-desktop:<path>`). An un-rendered placeholder yields [].
    property var apps: { var a = @@APPS@@; return (a instanceof Array) ? a : [] }

    property string filter: ""
    property int selectedIndex: 0

    property var view: {
        var f = filter.toLowerCase()
        if (!f) return apps
        var out = []
        for (var i = 0; i < apps.length; i++)
            if (apps[i].label.toLowerCase().indexOf(f) !== -1) out.push(apps[i])
        return out
    }
    onViewChanged: selectedIndex = 0

    function activate(node) {
        if (!node) return
        if (node.action) sendCmd(node.action)
        Qt.quit()
    }
    function enter() {
        if (view.length === 0) return
        activate(view[Math.max(0, Math.min(selectedIndex, view.length - 1))])
    }
    function moveSel(delta) {
        if (view.length === 0) return
        selectedIndex = (selectedIndex + delta + view.length) % view.length
    }

    // ---- click outbox (SQLite drained by the launcher) -----------------------
    function sendCmd(cmd) {
        try {
            var db = LocalStorage.openDatabaseSync("omasteam_apps", "1.0", "omasteam apps outbox", 100000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS apps_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO apps_outbox(cmd) VALUES(?)", [cmd])
            })
        } catch (e) { console.log("sendCmd failed:", e) }
    }

    // ---- surface -------------------------------------------------------------
    // Full-window scrim (matches the menu): dims the desktop ~40% AND forces a
    // full repaint each frame so a shrinking filtered list can't ghost.
    Rectangle {
        anchors.fill: parent
        color: win.alpha(win.cBg, 0.4)
    }
    MouseArea { anchors.fill: parent; onClicked: Qt.quit() }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: 460
        // 24 = the Column's top+bottom margins; inner.spacing sits between the
        // header and the list (without it the list overflowed the bottom margin).
        height: header.height + inner.spacing + list.contentHeightClamped + 24
        radius: 14
        color: win.cBg
        border.color: win.alpha(win.cFg, 0.12)
        border.width: 1
        MouseArea { anchors.fill: parent }

        Column {
            id: inner
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Item {
                id: header
                width: parent.width
                height: 40

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    color: win.alpha(win.cFg, 0.06)

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.icoSearch
                            color: win.alpha(win.cFg, 0.55)
                            font { family: win.fontFamily; pixelSize: 14 }
                        }

                        TextInput {
                            id: input
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 60
                            color: win.cFg
                            font { family: win.fontFamily; pixelSize: 14 }
                            focus: true
                            selectByMouse: true
                            clip: true
                            onTextChanged: win.filter = text
                            Component.onCompleted: forceActiveFocus()
                            // Static (non-blinking) cursor — a blinking cursor
                            // repaints ~1×/sec and would accumulate the scrim.
                            cursorDelegate: Rectangle { width: 2; color: win.cAccent }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: input.text.length === 0
                                text: "Search apps…"
                                color: win.alpha(win.cFg, 0.4)
                                font { family: win.fontFamily; pixelSize: 14 }
                            }

                            Keys.onPressed: function(e) {
                                switch (e.key) {
                                case Qt.Key_Down:   win.moveSel(1);  e.accepted = true; break
                                case Qt.Key_Up:     win.moveSel(-1); e.accepted = true; break
                                case Qt.Key_Return:
                                case Qt.Key_Enter:  win.enter();     e.accepted = true; break
                                case Qt.Key_Escape: Qt.quit();       e.accepted = true; break
                                case Qt.Key_Tab:    win.moveSel(1);  e.accepted = true; break
                                }
                            }
                        }
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                readonly property int rowH: 40
                readonly property int contentHeightClamped: Math.min(win.view.length, 9) * rowH
                height: contentHeightClamped
                model: win.view
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
                            width: 20
                            text: win.icoApp
                            color: sel ? win.cBg : win.cAccent
                            font { family: win.fontFamily; pixelSize: 16 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label || ""
                            color: sel ? win.cBg : win.cFg
                            font { family: win.fontFamily; pixelSize: 14; bold: sel }
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
