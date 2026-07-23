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
    // MUST set an explicit full-screen size. Unlike Quickshell's PanelWindow
    // (what Omarchy uses), a plain qmlscene Window with org.kde.layershell does
    // NOT derive its size from the all-edge anchors — with no width/height it
    // falls back to a default (~3/4 screen) and renders as a centered box, so the
    // scrim leaves a transparent margin all around. Pinning Screen.width/height
    // makes the layer surface cover the whole output. (Verified with a bordered
    // probe: the green frame sat on all four screen edges only once these were set.)
    width: Screen.width
    height: Screen.height

    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    // Don't set exclusionZone: -1 — under org.kde.layershell + qmlscene it makes
    // the box problem worse, not better. The explicit size above is what fills.
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

    // Only reassign win.st when state.json actually CHANGED. Reassigning it every
    // tick (even to identical values) re-dirties the palette bindings, which
    // repaints the full-window scrim — and on this transparent layer-shell surface
    // a scrim repaint blends over the previous frame instead of replacing it, so
    // the dim slowly accumulates toward opaque ("the background keeps getting
    // darker"). Skipping the no-op reassignment keeps the scrim static.
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
    // Poll ONCE at open — the menu is transient and the theme palette can't change
    // while it's up (picking a theme closes the menu). A repeating timer would
    // re-read state.json every tick; even guarded, that's a periodic repaint risk
    // on this accumulation-prone transparent surface, and it's simply not needed.
    Component.onCompleted: poll()

    // ---- Nerd Font (FontAwesome) glyphs --------------------------------------
    // Kept as codepoints so this source stays ASCII-clean and unambiguous.
    function g(cp) { return String.fromCodePoint(cp) }
    // omasteam chrome
    readonly property string icoCapture: g(0xF030)  // camera
    readonly property string icoStyle:   g(0xF1FC)  // paint-brush
    readonly property string icoSystem:  g(0xF011)  // power-off
    readonly property string icoChevron: g(0xF054)  // chevron-right (submenu marker)
    readonly property string icoSearch:  g(0xF002)  // magnifier
    // KDE settings categories (mirror systemsettings' sidebar)
    readonly property string icoDisplay:  g(0xF108)  // desktop
    readonly property string icoAccess:   g(0xF29A)  // universal-access
    readonly property string icoDevices:  g(0xF1E6)  // plug
    readonly property string icoNet:      g(0xF0AC)  // globe
    readonly property string icoLook:     g(0xF53F)  // palette
    readonly property string icoWindows:  g(0xF2D0)  // window-maximize
    readonly property string icoSound:    g(0xF028)  // volume-up
    readonly property string icoPowerMgt: g(0xF0E7)  // bolt
    readonly property string icoInput:    g(0xF11C)  // keyboard
    readonly property string icoWork:     g(0xF0DB)  // columns
    readonly property string icoSecurity: g(0xF023)  // lock
    readonly property string icoStartup:  g(0xF135)  // rocket
    readonly property string icoLang:     g(0xF1AB)  // language
    readonly property string icoUsers:    g(0xF0C0)  // users
    readonly property string icoInfo:     g(0xF05A)  // info-circle
    readonly property string icoAllSet:   g(0xF085)  // cogs

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

    // The menu IS the system-settings surface (apps live in the separate
    // omasteam-apps launcher now). Top level mirrors KDE systemsettings' sidebar;
    // each leaf's `kcm:<module>` action opens that module via kcmshell6. omasteam's
    // own chrome (Style / Capture / Power) sits at the bottom.
    property var menuTree: [
        { glyph: icoDisplay,  label: "Display & Monitor", children: [
            { glyph: g(0xF108), label: "Display Configuration", action: "kcm:kcm_kscreen" },
            { glyph: g(0xF186), label: "Night Light",           action: "kcm:kcm_nightlight" },
        ]},
        { glyph: icoAccess,   label: "Accessibility", action: "kcm:kcm_access" },
        { glyph: icoDevices,  label: "Connected Devices", children: [
            { glyph: g(0xF294), label: "Bluetooth",       action: "kcm:kcm_bluetooth" },
            { glyph: g(0xF0A0), label: "Disks & Cameras", action: "kcm:kcm_device_automounter" },
            { glyph: g(0xF0E7), label: "Thunderbolt",     action: "kcm:kcm_bolt" },
            { glyph: g(0xF10B), label: "KDE Connect",     action: "kcm:kcm_kdeconnect" },
            { glyph: g(0xF02F), label: "Printers",        action: "kcm:kcm_printer_manager" },
        ]},
        { glyph: icoNet,      label: "Networking", children: [
            { glyph: g(0xF1EB), label: "Wi-Fi & Internet",    action: "wifi" },
            { glyph: g(0xF0E8), label: "Network Connections", action: "kcm:kcm_networkmanagement" },
            { glyph: g(0xF2BD), label: "Online Accounts",     action: "kcm:kcm_kaccounts" },
            { glyph: g(0xF108), label: "Remote Desktop",      action: "kcm:kcm_krdpserver" },
        ]},
        { glyph: icoLook,     label: "Appearance & Style", children: [
            { glyph: g(0xF03E), label: "Wallpaper",    action: "kcm:kcm_wallpaper" },
            { glyph: g(0xF53F), label: "Colors",       action: "kcm:kcm_colors" },
            { glyph: g(0xF1FC), label: "Plasma Style", action: "kcm:kcm_desktoptheme" },
            { glyph: g(0xF042), label: "Global Theme", action: "kcm:kcm_lookandfeel" },
            { glyph: g(0xF009), label: "Icons",        action: "kcm:kcm_icons" },
            { glyph: g(0xF245), label: "Cursors",      action: "kcm:kcm_cursortheme" },
            { glyph: g(0xF031), label: "Text & Fonts", action: "kcm:kcm_fonts" },
            { glyph: g(0xF04B), label: "Animations",   action: "kcm:kcm_animations" },
        ]},
        { glyph: icoWindows,  label: "Apps & Windows", children: [
            { glyph: g(0xF085), label: "Default Applications", action: "kcm:kcm_componentchooser" },
            { glyph: g(0xF0F3), label: "Notifications",        action: "kcm:kcm_notifications" },
            { glyph: g(0xF2D0), label: "Window Behavior",      action: "kcm:kcm_kwinoptions" },
            { glyph: g(0xF022), label: "Window Rules",         action: "kcm:kcm_kwinrules" },
            { glyph: g(0xF050), label: "Task Switcher",        action: "kcm:kcm_kwintabbox" },
            { glyph: g(0xF065), label: "Screen Edges",         action: "kcm:kcm_kwinscreenedges" },
            { glyph: g(0xF074), label: "Activities",           action: "kcm:kcm_activities" },
        ]},
        { glyph: icoSound,    label: "Sound",            action: "kcm:kcm_pulseaudio" },
        { glyph: icoPowerMgt, label: "Power Management", action: "kcm:kcm_powerdevilprofilesconfig" },
        { glyph: icoInput,    label: "Input Devices", children: [
            { glyph: g(0xF11C), label: "Keyboard",        action: "kcm:kcm_keyboard" },
            { glyph: g(0xF084), label: "Shortcuts",       action: "kcm:kcm_keys" },
            { glyph: g(0xF245), label: "Mouse",           action: "kcm:kcm_mouse" },
            { glyph: g(0xF0A6), label: "Touchpad",        action: "kcm:kcm_touchpad" },
            { glyph: g(0xF11B), label: "Game Controller", action: "kcm:kcm_gamecontroller" },
        ]},
        { glyph: icoWork,     label: "Workspace", children: [
            { glyph: g(0xF013), label: "General Behavior",  action: "kcm:kcm_workspace" },
            { glyph: g(0xF002), label: "Search",            action: "kcm:kcm_plasmasearch" },
            { glyph: g(0xF0DB), label: "Virtual Desktops",  action: "kcm:kcm_kwin_virtualdesktops" },
        ]},
        { glyph: icoSecurity, label: "Security & Privacy", children: [
            { glyph: g(0xF023), label: "Screen Locking",         action: "kcm:kcm_screenlocker" },
            { glyph: g(0xF132), label: "Application Permissions", action: "kcm:kcm_flatpak" },
            { glyph: g(0xF1DA), label: "Recent Files",           action: "kcm:kcm_recentFiles" },
            { glyph: g(0xF075), label: "User Feedback",          action: "kcm:kcm_feedback" },
        ]},
        { glyph: icoStartup,  label: "Startup & Shutdown", children: [
            { glyph: g(0xF04B), label: "Autostart",           action: "kcm:kcm_autostart" },
            { glyph: g(0xF085), label: "Background Services",  action: "kcm:kcm_kded" },
            { glyph: g(0xF08B), label: "Desktop Session",      action: "kcm:kcm_smserver" },
            { glyph: g(0xF007), label: "Login Screen",         action: "kcm:kcm_sddm" },
        ]},
        { glyph: icoLang,     label: "Language & Time", children: [
            { glyph: g(0xF1AB), label: "Region & Language", action: "kcm:kcm_regionandlang" },
            { glyph: g(0xF017), label: "Date & Time",       action: "kcm:kcm_clock" },
            { glyph: g(0xF00C), label: "Spell Check",       action: "kcm:kcmspellchecking" },
        ]},
        { glyph: icoUsers,    label: "Users",             action: "kcm:kcm_users" },
        { glyph: icoInfo,     label: "About This System", action: "kcm:kcm_about-distro" },
        { glyph: icoAllSet,   label: "Open Full System Settings", action: "settings" },
        // ---- omasteam chrome ----
        { glyph: icoStyle,   label: "Style", children: [
            { glyph: g(0xF03E), label: "Next Wallpaper", action: "wallpaper-next" },
            { glyph: g(0xF1FC), label: "Themes",         children: themeChildren() },
        ]},
        { glyph: icoCapture, label: "Capture", children: [
            { glyph: g(0xF125), label: "Screenshot Region", action: "shot-region" },
            { glyph: g(0xF2D0), label: "Screenshot Window", action: "shot-window" },
            { glyph: g(0xF108), label: "Screenshot Full",   action: "shot-full" },
            { glyph: g(0xF03D), label: "Record Screen",     action: "record" },
        ]},
        { glyph: icoSystem,  label: "Power", children: [
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
    // Full-window scrim, exactly like Omarchy quattro's menu: its Menu.qml paints
    // a `color: root.scrim` rectangle behind the card, where scrim = the theme
    // background at scrim-alpha 0.5 (Color.qml + shell.toml). Two jobs:
    //   1. matches the reference look — Omarchy dims the desktop ~50% behind the
    //      menu (it is NOT an undimmed float);
    //   2. this painted full-window node forces a full repaint every frame, which
    //      is what stops a shrinking panel from ghosting. With a fully transparent
    //      backdrop, QtQuick's partial (damaged-region) updates leave the strip a
    //      shrinking/back-navigating panel vacates un-cleared, so old rows linger.
    Rectangle {
        anchors.fill: parent
        color: win.alpha(win.cBg, 0.4)
    }
    // Click anywhere outside the panel dismisses (the panel absorbs its own clicks).
    MouseArea { anchors.fill: parent; onClicked: Qt.quit() }

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
                            // Static (non-blinking) cursor. A blinking cursor repaints
                            // ~1×/sec, and on this transparent layer-shell surface any
                            // repaint re-blends the scrim and darkens it over time.
                            cursorDelegate: Rectangle { width: 2; color: win.cAccent }

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
