// omasteam-menu — an Omarchy-style system menu for SteamOS + KDE, in pure QML.
//
// A transient full-screen Wayland layer-shell OVERLAY (via org.kde.layershell,
// already on SteamOS) launched on demand by `omasteam-menu` and bound to
// Meta+Alt+Space. Walker-style: type-to-filter + arrow keys + Enter/Esc, nested
// categories, theme-synced from the active omasteam palette.
//
// Same "QML front, bash back" split as the bar: plain qmlscene can't spawn
// processes, so the leaf action-id is pushed to a SQLite outbox and the
// launcher (which waits for this window to close) runs the real command.
//
// NOTE: the outbox table is named `menu_outbox`, NOT `outbox`. The bar daemon
// drains every DB that has a table called `outbox`; a different name keeps our
// menu commands out of its reach.
import QtQuick
import QtQuick.Window
import QtQuick.LocalStorage
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"

    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    // Grab the keyboard while the menu is up (the bar uses None; the menu is modal).
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive

    // ---- theme palette (read from the bar daemon's state.json, like the bar) --
    property var st: ({})
    readonly property color cBg: st.colors ? st.colors.bg : "#1a1b26"
    readonly property color cFg: st.colors ? st.colors.fg : "#c0caf5"
    readonly property color cAccent: st.colors ? st.colors.accent : "#7aa2f7"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    // The launcher renders @@STATE@@ to the absolute state.json path (qmlscene
    // can't read argv/env reliably). An un-rendered placeholder disables polling
    // and the hardcoded fallback palette above is used instead.
    readonly property string statePath: { var p = "@@STATE@@"; return p.charAt(0) === "/" ? p : "" }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    function poll() {
        if (!statePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                try { win.st = JSON.parse(xhr.responseText) } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + statePath)
        xhr.send()
    }
    Component.onCompleted: poll()
    Timer { interval: 500; running: true; repeat: true; onTriggered: win.poll() }

    // ---- Nerd Font (FontAwesome) glyphs --------------------------------------
    // Kept as codepoints so this source stays ASCII-clean and unambiguous.
    function g(cp) { return String.fromCodePoint(cp) }
    readonly property string icoApps:    g(0xF00A)  // th (grid)
    readonly property string icoCapture: g(0xF030)  // camera
    readonly property string icoStyle:   g(0xF1FC)  // paint-brush
    readonly property string icoSetup:   g(0xF013)  // cog
    readonly property string icoSystem:  g(0xF011)  // power-off
    readonly property string icoChevron: g(0xF054)  // chevron-right (submenu marker)
    readonly property string icoSearch:  g(0xF002)  // magnifier

    // ---- menu tree -----------------------------------------------------------
    // Leaf nodes carry `action` (an id the launcher dispatches); branch nodes
    // carry `children`. The Style > Themes level is filled from @@THEMES@@.
    property var themeList: { var t = @@THEMES@@; return (t instanceof Array) ? t : [] }
    readonly property string currentTheme: "@@CURRENT_THEME@@"

    function themeChildren() {
        var out = []
        for (var i = 0; i < themeList.length; i++) {
            var name = themeList[i]
            var mark = (name === currentTheme) ? "  " + String.fromCodePoint(0xF00C) : ""  // check
            out.push({ glyph: g(0xF043), label: name + mark, action: "theme-set:" + name })
        }
        if (out.length === 0)
            out.push({ glyph: g(0xF071), label: "No themes installed", action: "" })
        return out
    }

    property var menuTree: [
        { glyph: icoApps,    label: "Apps",    action: "apps" },
        { glyph: icoCapture, label: "Capture", children: [
            { glyph: g(0xF125), label: "Screenshot Region", action: "shot-region" },
            { glyph: g(0xF2D0), label: "Screenshot Window", action: "shot-window" },
            { glyph: g(0xF108), label: "Screenshot Full",   action: "shot-full" },
            { glyph: g(0xF03D), label: "Record Screen",     action: "record" },
        ]},
        { glyph: icoStyle,   label: "Style",   children: [
            { glyph: g(0xF03E), label: "Next Wallpaper", action: "wallpaper-next" },
            { glyph: g(0xF1FC), label: "Themes",         children: themeChildren() },
        ]},
        { glyph: icoSetup,   label: "Setup",   children: [
            { glyph: g(0xF1EB), label: "Wi-Fi",      action: "wifi" },
            { glyph: g(0xF294), label: "Bluetooth",  action: "bluetooth" },
            { glyph: g(0xF028), label: "Audio",      action: "audio" },
            { glyph: g(0xF108), label: "Display",    action: "display" },
            { glyph: g(0xF186), label: "Night Light",action: "nightlight" },
        ]},
        { glyph: icoSystem,  label: "System",  children: [
            { glyph: g(0xF023), label: "Lock",             action: "lock" },
            { glyph: g(0xF186), label: "Suspend",          action: "suspend" },
            { glyph: g(0xF08B), label: "Log Out",          action: "logout" },
            { glyph: g(0xF021), label: "Restart",          action: "restart" },
            { glyph: g(0xF011), label: "Shut Down",        action: "shutdown" },
            { glyph: g(0xF1B6), label: "Return to Gaming", action: "return-to-gaming" },
        ]},
    ]

    // ---- navigation state ----------------------------------------------------
    // stack: array of levels [{title, items}]. Always REASSIGNED (never mutated)
    // so the `view` binding re-evaluates.
    property var stack: [{ title: "", items: menuTree }]
    property string filter: ""
    property int selectedIndex: 0

    readonly property string crumb: stack[stack.length - 1].title

    // filtered items for the current level
    property var view: {
        var items = stack[stack.length - 1].items
        var f = filter.toLowerCase()
        if (!f) return items
        var out = []
        for (var i = 0; i < items.length; i++)
            if (items[i].label.toLowerCase().indexOf(f) !== -1) out.push(items[i])
        return out
    }
    onViewChanged: selectedIndex = 0

    function openBranch(node) {
        stack = stack.concat([{ title: node.label, items: node.children }])
        filter = ""
    }
    function activate(node) {
        if (!node) return
        if (node.children) { openBranch(node); return }
        if (node.action) sendCmd(node.action)
        Qt.quit()
    }
    function enter() {
        if (view.length === 0) return
        activate(view[Math.max(0, Math.min(selectedIndex, view.length - 1))])
    }
    function back() {
        if (filter.length > 0) { filter = ""; return }
        if (stack.length > 1) { stack = stack.slice(0, stack.length - 1); return }
        Qt.quit()
    }
    function moveSel(delta) {
        if (view.length === 0) return
        selectedIndex = (selectedIndex + delta + view.length) % view.length
    }

    // ---- click outbox (SQLite drained by the launcher) -----------------------
    // Table `menu_outbox` (see file header) so the bar daemon leaves it alone.
    function sendCmd(cmd) {
        try {
            var db = LocalStorage.openDatabaseSync("omasteam_menu", "1.0", "omasteam menu outbox", 100000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS menu_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO menu_outbox(cmd) VALUES(?)", [cmd])
            })
        } catch (e) { console.log("sendCmd failed:", e) }
    }

    // ---- surface -------------------------------------------------------------
    // Dimmed backdrop; a click anywhere outside the panel dismisses.
    Rectangle {
        anchors.fill: parent
        color: win.alpha(win.cBg, 0.55)
        MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: 460
        height: header.height + list.contentHeightClamped + 24
        radius: 14
        color: win.cBg
        border.color: win.alpha(win.cFg, 0.12)
        border.width: 1
        // Absorb clicks so they don't fall through to the dismiss backdrop.
        MouseArea { anchors.fill: parent }

        Column {
            id: inner
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ---- header: search field + breadcrumb ----
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

                            // Placeholder / breadcrumb hint when empty.
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: input.text.length === 0
                                text: win.crumb ? ("Search " + win.crumb + "…") : "Search…"
                                color: win.alpha(win.cFg, 0.4)
                                font { family: win.fontFamily; pixelSize: 14 }
                            }

                            Keys.onPressed: function(e) {
                                switch (e.key) {
                                case Qt.Key_Down:      win.moveSel(1);  e.accepted = true; break
                                case Qt.Key_Up:        win.moveSel(-1); e.accepted = true; break
                                case Qt.Key_Return:
                                case Qt.Key_Enter:     win.enter();     e.accepted = true; break
                                case Qt.Key_Escape:    win.back();      e.accepted = true; break
                                case Qt.Key_Right:
                                    if (win.view.length && win.view[win.selectedIndex] && win.view[win.selectedIndex].children) {
                                        win.enter(); e.accepted = true
                                    }
                                    break
                                case Qt.Key_Left:      win.back();      e.accepted = true; break
                                case Qt.Key_Backspace:
                                    if (input.text.length === 0 && win.stack.length > 1) { win.back(); e.accepted = true }
                                    break
                                case Qt.Key_Tab:       win.moveSel(1);  e.accepted = true; break
                                }
                            }
                        }
                    }
                }
            }

            // ---- rows ----
            ListView {
                id: list
                width: parent.width
                // Clamp height so the panel grows with content but caps at ~9 rows.
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
                            text: modelData.glyph || ""
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

                    // submenu marker on the right
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        visible: modelData.children !== undefined
                        text: win.icoChevron
                        color: sel ? win.alpha(win.cBg, 0.7) : win.alpha(win.cFg, 0.4)
                        font { family: win.fontFamily; pixelSize: 12 }
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
